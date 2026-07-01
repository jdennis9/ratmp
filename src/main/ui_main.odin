/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
#+private file
package main

import "core:sync"
import "core:thread"
import "core:math/linalg"
import "base:runtime"
import "core:strconv"
import "core:reflect"
import "src:dsp"
import "core:sort"
import "core:path/filepath"
import "core:os"
import "core:encoding/json"
import "core:math/rand"
import "core:log"
import "core:strings"
import "core:mem"
import "core:container/handle_map"
import "src:imx"
import imgui "src:thirdparty/odin-imgui"
import "core:time"
import "core:fmt"

ICON_VOLUME_OFF     :: ""
ICON_VOLUME_LOW     :: ""
ICON_VOLUME_MEDIUM  :: ""
ICON_VOLUME_HIGH    :: ""
ICON_SHUFFLE        :: ""
ICON_ARROW_RIGHT    :: ""
ICON_PREVIOUS_TRACK :: ""
ICON_NEXT_TRACK     :: ""
ICON_PAUSE          :: ""
ICON_STOP           :: ""
ICON_PLAY           :: ""
ICON_MAGNIFY        :: ""

_ANALYSIS_BUFFER_SIZE :: (16<<10)

// -----------------------------------------------------------------------------
// Track table
// -----------------------------------------------------------------------------

_Track_Table_Row :: struct {
	title:      string,
	url:        string,
	id:         Track_ID,
	artists:    Track_Group_ID_Set,
	genres:     Track_Group_ID_Set,
	album:      Album_ID,
	format:     Audio_File_Format,
	samplerate: [8]u8,
	duration:   [8]u8,
	year:       [4]u8,
	bitrate:    [9]u8,
	track_no:   [3]u8,
	selected:   bool,
}

_Track_Table :: struct {
	filter_buf:     [512]u8,
	filter_metrics: bit_set[Track_Filter_Metric],
	filter_hash:    u32,
	sort_spec:      Maybe(Track_Sort_Spec),
	serial:         uint,
	playlist_uid:   UID,
	rows:           [dynamic]_Track_Table_Row,
	scratch:        mem.Scratch,
}

// -----------------------------------------------------------------------------
// Windows
// -----------------------------------------------------------------------------

_Window_ID :: enum {
	Library,
	Queue,
	Playlists,
	Artists,
	Albums,
	Genres,
	Metadata,
	ThemeEditor,
	Oscilloscope,
	Spectrum,
	Wavebar,
	Settings,
	PostProcessing,
	FolderTree,
	Licenses,
}

_Window_Category :: enum {
	Music,
	Visualizers,
	Settings,
}

_Window_Flag :: enum {DefaultShow, AlwaysShow, DontSave}
_Window_Flags :: bit_set[_Window_Flag]

_Window_Args :: union {
	Track_ID, // Metadata window
}

_Window_Info :: struct {
	title,              internal_name: cstring,
	flags:              _Window_Flags,
	imgui_flags:        imgui.WindowFlags,
	show_proc:          proc(ui: ^UI) -> bool,
	settings_load_proc: proc(ui: ^UI, key, value: string) -> Error,
	settings_save_proc: proc(ui: ^UI, output: ^map[string]string, allocator: mem.Allocator) -> Error,
}

_WINDOW_INFO := [_Window_ID]_Window_Info {
	.Library = {
		title = "Library",
		internal_name = "_library",
		flags = {.DefaultShow, .AlwaysShow},

		show_proc = proc(ui: ^UI) -> bool {
			sv := ui.server
			w := &ui.windows.library

			if w.serial != sv.library.serial {
				delete(w.tracks)
				w.serial = sv.library.serial
				w.tracks = library_get_all_tracks(sv.library, context.allocator) or_else nil
			}

			_track_table_show(
				ui, "##library", &w.track_table, sv.library.serial, w.tracks, {}, 0
			)

			return true
		},
	},
	.Queue = {
		title = "Queue",
		internal_name = "_queue",
		flags = {.DefaultShow},

		show_proc = proc(ui: ^UI) -> bool {
			sv := ui.server
			w := &ui.windows.queue

			_track_table_show(
				ui, "##queue", &w.track_table, sv.playback.serial,
				server_get_queue(sv), {.IsQueue}, sv.queue_uid,
			)

			return true
		}

	},
	.Playlists = {
		title = "Playlists",
		internal_name = "_playlists",
		flags = {.DefaultShow},
		show_proc = proc(ui: ^UI) -> bool {
			return _playlists_window_show(ui, &ui.windows.playlists)
		},
	},
	.Artists = {
		title = "Artists",
		internal_name = "_artists",
		show_proc = proc(ui: ^UI) -> bool {
			sv := ui.server
			_track_group_window_show_focused(ui, &ui.windows.artists,.Artist)
			return true
		},
	},
	.Albums = {
		title = "Albums",
		internal_name = "_albums",
		flags = {.DefaultShow},
		show_proc = proc(ui: ^UI) -> bool {
			sv := ui.server
			_track_group_window_show_focused(ui, &ui.windows.albums, .Album)
			return true
		},
	},
	.Genres = {
		title = "Genres",
		internal_name = "_genres",
		show_proc = proc(ui: ^UI) -> bool {
			sv := ui.server
			_track_group_window_show_focused(ui, &ui.windows.genres, .Genre)
			return true
		},
	},
	.Metadata = {
		title = "Metadata",
		internal_name = "_metadata",
		flags = {.DefaultShow},
		imgui_flags = {.AlwaysVerticalScrollbar},
		show_proc = proc(ui: ^UI) -> bool {
			return _metadata_window_show(ui, &ui.windows.metadata, ui.server.current_track_id)
		},
	},
	.ThemeEditor = {
		title = "Edit Theme",
		internal_name = "_theme_editor",
		show_proc = _theme_editor_show,
	},
	.Oscilloscope = {
		title = "Oscilloscope",
		internal_name = "_oscilloscope",
		show_proc = proc(ui: ^UI) -> bool {
			return _oscilloscope_window_show(ui, &ui.windows.oscilloscope)
		},
		settings_save_proc = proc(ui: ^UI, output: ^map[string]string, allocator: mem.Allocator) -> Error {
			return _oscilloscope_window_get_settings(ui, &ui.windows.oscilloscope, output, allocator)
		},
		settings_load_proc = proc(ui: ^UI, key, value: string) -> Error {
			return _oscilloscope_window_load_setting(ui, &ui.windows.oscilloscope, key, value)
		},
	},
	.Spectrum = {
		title = "Spectrum",
		internal_name = "_spectrum",
		show_proc = proc(ui: ^UI) -> bool {
			return _spectrum_window_show(ui, &ui.windows.spectrum)
		},
		settings_save_proc = proc(ui: ^UI, output: ^map[string]string, allocator: mem.Allocator) -> Error {
			return _spectrum_window_get_settings(ui, &ui.windows.spectrum, output, allocator)
		},
		settings_load_proc = proc(ui: ^UI, key, value: string) -> Error {
			return _spectrum_window_load_setting(ui, &ui.windows.spectrum, key, value)
		},
	},
	.Wavebar = {
		title = "Wavebar",
		internal_name = "_wavebar",
		show_proc = proc(ui: ^UI) -> bool {
			return _wavebar_window_show(ui, &ui.windows.wavebar)
		},
		settings_save_proc = proc(ui: ^UI, output: ^map[string]string, allocator: mem.Allocator) -> Error {
			return _wavebar_window_get_settings(ui, &ui.windows.wavebar, output, allocator)
		},
		settings_load_proc = proc(ui: ^UI, key, value: string) -> Error {
			return _wavebar_window_load_setting(&ui.windows.wavebar, key, value)
		}
	},
	.Settings = {
		title = "Edit Settings",
		internal_name = "_settings",
		flags = {.DontSave},
		show_proc = proc(ui: ^UI) -> bool {
			if _show_settings_editor(ui) {
				global_config_dirty = true
				return true
			}

			return false
		},
	},
	.PostProcessing = {
		title = "Post Processing",
		internal_name = "_post_processing",
		show_proc = proc(ui: ^UI) -> bool {
			return _post_processing_window_show(ui, &ui.windows.post_processing)
		},
	},
	.FolderTree = {
		title = "Folders",
		internal_name = "_folder_tree",

		show_proc = proc(ui: ^UI) -> bool {
			_folder_tree_window_show_focused(ui, &ui.windows.folder_tree)
			return true
		}
	},
	.Licenses = {
		title = "Licenses",
		internal_name = "_licenses",

		show_proc = proc(ui: ^UI) -> bool {
			mpl := get_license()
			imx.title_text(mpl.name)
			imx.text_unformatted(PROGRAM_LICENSE)
			imgui.TextLinkOpenURL(mpl.url)

			for l in get_third_party_licenses() {
				imx.title_text(l.name)
				imgui.Text(l.ownage)
				imgui.TextLinkOpenURL(l.url)
			}

			return true
		},
	},
}

// -----------------------------------------------------------------------------
// Metadata window
// -----------------------------------------------------------------------------

_Metadata_Window :: struct {
	displayed_track: Track_ID,
	cover_art:       Maybe(Texture_Handle),
	cover_width:     int,
	cover_height:    int,
	cover_file_size: int,
	should_crop_art: bool,
	comment:         string,
}

_Playlists_Window :: struct {
	new_playlist_name:        [128]u8,
	playlist_table:           _Playlist_Table,
	track_table:              _Track_Table,
	viewing_playlist:         Maybe(Playlist_Handle),
	cant_add_playlist_reason: Cant_Add_Playlist_Reason,
}

// -----------------------------------------------------------------------------
// Track group window
// -----------------------------------------------------------------------------

_TRACK_COMMON_STRING_TYPE_NAMES := [Track_Group_Type]cstring {
	.Artist = "Artists",
	.Genre  = "Genres",
	.Album  = "Albums",
}

_Track_Group_Window :: struct {
	playlist_table:     _Playlist_Table,
	track_table:        _Track_Table,
	filter_buf:         [128]u8,
	filter_hash:        u32,
	displayed_entry_id: Maybe(i16),
	tracks:             [dynamic]Track_ID,
}

// -----------------------------------------------------------------------------
// Oscilloscope window
// -----------------------------------------------------------------------------

_Oscilloscope_Display_Mode :: enum {
	Average,
	Layered,
	Stacked,
}

_OSCILLOSCOPE_MIN_SAMPLES :: 100
_OSCILLOSCOPE_MAX_SAMPLES :: 16000

_Oscilloscope_Window :: struct {
	window_size:  int,
	position_buf: [][2]f32,
	audio_ring:   Ring_Buffer(f32),
	pinch_ends:   bool,
	display_mode: _Oscilloscope_Display_Mode,
}

// -----------------------------------------------------------------------------
// Spectrum window
// -----------------------------------------------------------------------------

_Spectrum_Display_Mode :: enum {
	Histogram,
	Heat,
	Line,
	LineFilled,
}

SPECTRUM_MAX_BANDS :: 160
_SPECTRUM_WINDOW_SIZE :: 8<<10

_Spectrum_Frequency_Guide :: struct {
	str: [8]u8,
	offset: f32,
}

_Spectrum_Window :: struct {
	bands:            [dynamic; SPECTRUM_MAX_BANDS]f32,
	band_freqs:       [dynamic; SPECTRUM_MAX_BANDS]f32,
	freq_guides:      [dynamic; 32]_Spectrum_Frequency_Guide,
	window_values:    [dynamic]f32,
	fft:              dsp.FFT_State,
	display_mode:     _Spectrum_Display_Mode,
	window_func:      dsp.Window_Function,
	band_gap:         f32,
	freq_guide_width: f32, // Width of spectrum window when frequency guides were built
	freq_guide_bands: int,
}

// -----------------------------------------------------------------------------
// Post processing
// -----------------------------------------------------------------------------

_Post_Processing_Window :: struct {
	params: Playback_Post_Process_Params,
}

// -----------------------------------------------------------------------------
// Wavebar
// -----------------------------------------------------------------------------

_WAVEBAR_NUM_DATA_POINTS :: 1440

_Wavebar_Builder :: struct {
	data_points: [_WAVEBAR_NUM_DATA_POINTS]f32,
	data_points_calculated: int,
	want_cancel: bool,
	track_url: string,
}

_Wavebar_Window :: struct {
	bg: _Wavebar_Builder,
	decoder_thread: ^thread.Thread,
	displayed_track: Track_ID,
	color_mode: imx.Bar_Color_Mode,
}

// -----------------------------------------------------------------------------
// Folder tree
// -----------------------------------------------------------------------------

_Folder_Tree_Node :: struct {
	totals:   Track_List_Totals,
	children: []_Folder_Tree_Node,
	name:     cstring,
	origin:   ^Library_Folder,
}

_Folder_Tree_Window :: struct {
	selected_folder_hash:   u64,
	selected_folder_serial: uint,
	selected_folder:        ^_Folder_Tree_Node,
	tree_serial:            uint,
	root_node:              _Folder_Tree_Node,
	track_table:            _Track_Table,
	tracks:                 [dynamic]Track_ID,
}

// -----------------------------------------------------------------------------
// Tracked window state
// -----------------------------------------------------------------------------

_Window_State :: struct {
	open:           bool,
	bring_to_front: bool,
	imgui_flags:    imgui.WindowFlags,
}

// -----------------------------------------------------------------------------
// Public types
// -----------------------------------------------------------------------------

@private
UI_Actions :: struct {
	minimize_to_tray: bool,
	exit:             bool,

	debug: struct {
		force_device_reset: bool,
		load_library:       bool,
		save_library:       bool,
	}
}

@private
UI :: struct {
	server:               ^Server,
	allocator_map:        Allocator_Map,
	actions:              UI_Actions,
	window_state:         [_Window_ID]_Window_State,
	sorted_window_states: []imgui.ID,
	system_fonts:         []System_Font,

	allocators: struct {
		per_frame:   mem.Allocator,
		themes:      mem.Allocator,
		fonts:       mem.Allocator,
		lazy:        mem.Allocator,
		analysis:    mem.Allocator,
		folder_tree: mem.Allocator,
	},

	windows: struct {
		library: struct {
			track_table: _Track_Table,
			tracks:      []Track_ID,
			serial:      uint,
		},
		
		queue: struct {
			serial:     uint,
			track_table: _Track_Table,
		},
		
		playlists:       _Playlists_Window,
		artists:         _Track_Group_Window,
		albums:          _Track_Group_Window,
		genres:          _Track_Group_Window,
		metadata:        _Metadata_Window,
		oscilloscope:    _Oscilloscope_Window,
		spectrum:        _Spectrum_Window,
		wavebar:         _Wavebar_Window,
		post_processing: _Post_Processing_Window,
		folder_tree:     _Folder_Tree_Window,
		
		show_settings: bool,
	},
	dialogs: struct {
		add_folder:     File_Dialog_State,
		set_background: File_Dialog_State,
		confirm_remove_missing_tracks: Message_Box_Handle,
	},
	background: struct {
		texture: Maybe(Texture_Handle),
		policy:  Image_Fit_Policy,
		size:    [2]f32,
		path:    string,
	},
	paths: struct {
		theme_folder: string,
	},
	analysis: struct {
		raw_output: [AUDIO_MAX_CHANNELS][]f32,
		avg_output: []f32, // Average of all channels for each frame
		samplerate: f32,
		channels:   int,
	},
	themes: [dynamic]_Theme,
	debug: struct {
		show_style_editor:    bool,
		show_demo_window:     bool,
		show_memory_tracking: bool,
	},
}

_Saved_Theme :: struct {
	name:         string,
	accents:      [_Theme_Accent][3]f32,
	colors:       [_Theme_Color]u32,
	imgui_colors: [imgui.Col.COUNT][4]f32,
}


// -----------------------------------------------------------------------------
// Theme
// -----------------------------------------------------------------------------

_Theme_Color :: enum {
	PlayingHighlight,
	LeftChannelWave,
	RightChannelWave,
	VolumeLow,
	VolumeHigh,
	WaveBarInner,
	WaveBarOuter,
}

_Theme_Accent :: enum {
	Fg1,
	Fg2,
	Bg,
}

_Theme :: struct {
	name: [128]u8,
	accents: [_Theme_Accent][3]f32,
	colors: [_Theme_Color]u32,
	imgui_colors: [imgui.Col.COUNT][4]f32,
	path: string,
}

ui_theme: _Theme

_THEME_COLOR_DEFAULTS := [_Theme_Color]u32 {
	.PlayingHighlight = 0xff0568fc,
	.LeftChannelWave  = 0xffffffff,
	.RightChannelWave = 0xff00ffff,
	.VolumeLow        = 0xff00ff00,
	.VolumeHigh       = 0xff0000ff,
	.WaveBarOuter     = 0xffffce00,
	.WaveBarInner     = 0xffff0800,
}

@private
ui_init :: proc(ui: ^UI, server: ^Server) -> Error {
	ui.server = server

	// Allocators
	ui.allocators.per_frame   = allocator_map_add_dynamic_arena(&ui.allocator_map, "per_frame", flags={.IsTemp})
	ui.allocators.fonts       = allocator_map_add_dynamic_arena(&ui.allocator_map, "fonts")
	ui.allocators.themes      = allocator_map_add_dynamic_arena(&ui.allocator_map, "themes", block_size=4096)
	ui.allocators.lazy        = allocator_map_add_dynamic_arena(&ui.allocator_map, "lazy")
	ui.allocators.folder_tree = allocator_map_add_dynamic_arena(&ui.allocator_map, "folder_tree", flags={.IsTemp})
	ui.allocators.analysis    = allocator_map_add_heap(&ui.allocator_map, "analysis")

	// Theme defaults
	ui_theme.imgui_colors = imgui.GetStyle().Colors
	ui_theme.colors = _THEME_COLOR_DEFAULTS
	
	// Paths
	ui.paths.theme_folder = filepath.join({global_paths.config_dir, "themes"}, context.allocator) or_return
	ensure_dir(ui.paths.theme_folder)
	
	_load_themes(ui)
	_refresh_fonts(ui)

	ui_apply_config(ui, global_config)

	// Windows
	for info, id in _WINDOW_INFO {
		if .DefaultShow in info.flags {
			ui.window_state[id].open = true
		}
	}

	// Settings handler
	{
		handler := imgui.SettingsHandler {
			ReadLineFn = _imgui_settings_read_line_proc,
			WriteAllFn = _imgui_settings_write_proc,
			ReadOpenFn = _imgui_settings_open_proc,
			UserData   = ui,
			TypeHash   = imgui.cImHashStr(PROGRAM_ID),
			TypeName   = PROGRAM_ID,
		}

		imgui.AddSettingsHandler(&handler)
	}

	ui.windows.post_processing.params = playback_thread_get_post_process_params(&server.playback_thread)

	return nil
}

@private
ui_shutdown :: proc(ui: ^UI) {
}

@private
ui_apply_config :: proc(ui: ^UI, the_cfg: Config) -> Error {
	cfg := the_cfg.ui

	log.debug("Applying UI config...")
	
	_set_background(ui, string(cfg.background), context.allocator)
	_set_theme_by_name(ui, string(cfg.default_theme))
	
	ui.background.policy = cfg.background_fit_policy

	DEFAULT_FONT_CONFIG :: imgui.FontConfig {
		FontDataOwnedByAtlas = true,
		GlyphMaxAdvanceX = max(f32),
		RasterizerMultiply = 1,
		RasterizerDensity = 1,
		ExtraSizeScale = 1,
	}

	imgui.FontAtlas_ClearFonts(imgui.GetIO().Fonts)

	add_font_from_memory :: proc(
		buf: []byte, merge: bool,
		scale_mod: f32 = 0,
	) -> Error {
		font_buf := raw_data(buf)
		
		cfg := DEFAULT_FONT_CONFIG
		cfg.ExtraSizeScale = 1 + scale_mod
		cfg.MergeMode = merge
		cfg.FontDataOwnedByAtlas = false

		imgui.FontAtlas_AddFontFromMemoryTTF(
			imgui.GetIO().Fonts, font_buf, auto_cast len(buf), font_cfg = &cfg
		)

		return nil
	}

	add_font_from_system_font :: proc(f: System_Font, merge: bool, scale_mod: f32 = 0) -> Error {
		path := font_get_path(f, context.allocator) or_return
		defer delete(path)

		if !os.exists(path) do return Custom_Error.NotFound

		buf: [512]u8
		set_cstring_buf(buf[:], path) or_return
		path_cstring := cstring(&buf[0])


		cfg := DEFAULT_FONT_CONFIG
		cfg.ExtraSizeScale = 1 + scale_mod
		cfg.MergeMode = merge

		imgui.FontAtlas_AddFontFromFileTTF(imgui.GetIO().Fonts, path_cstring, font_cfg = &cfg)

		return nil
	}

	loaded_font_count := 0

	for font in cfg.fonts {
		f := font_from_name(ui.system_fonts, string(font.name)) or_continue
		add_font_from_system_font(f, loaded_font_count > 0) or_continue
		loaded_font_count += 1
	}

	if loaded_font_count == 0 {
		add_font_from_memory(#load("data/NotoSans-SemiBold.ttf"), false) or_return
	}

	add_font_from_memory(
		#load("data/Font Awesome 7 Free-Solid-900.otf"), true, scale_mod = -0.2,
	) or_return

	return nil
}

@private
ui_show :: proc(ui: ^UI) -> (ui_actions: UI_Actions) {	
	sv := ui.server
	ui.actions = {}
	need_pop_font := false

	defer free_all(ui.allocators.per_frame)
	
	_update_analysis(ui)

	//style := imgui.GetStyle()
	//style.FontSizeBase = cfg.font_size != 0 ? clamp(f32(cfg.font_size), 8, 36) : 16
	if global_config.ui.font_size > 8 {
		imgui.PushFontFloat(nil, global_config.ui.font_size)
		need_pop_font = true
	}
	defer if need_pop_font do imgui.PopFont()

	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.PushStyleColor(.WindowBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor(2)

	// --------------------------------------------------------------------------
	// Remove missing tracks
	// --------------------------------------------------------------------------
	if res, have_res := message_box_get_response(
		ui.dialogs.confirm_remove_missing_tracks
	); have_res && res == .OkYes {
		tracks := library_get_missing_tracks(sv.library, ui.allocators.per_frame)
		library_remove_tracks(&sv.library, tracks)
		show_message_box_async(
			.Message, .Info, "Tracks Removed", "Removed", len(tracks), "missing tracks"
		)
	}

	// --------------------------------------------------------------------------
	// Add folders
	// --------------------------------------------------------------------------
	{
		results: [dynamic]Path
		defer delete(results)


		if async_file_dialog_get_results(&ui.dialogs.add_folder, &results) {
			input: [dynamic]Track_Scanner_Input
			defer delete(input)

			for &p in results {
				append(&input, Track_Scanner_Input {
					path = string(cstring(&p[0]))
				})
			}

			track_scanner_queue(&sv.track_scanner, input[:])
		}

	}

	// --------------------------------------------------------------------------
	// Set background
	// --------------------------------------------------------------------------
	{
		results: [dynamic]Path
		defer delete(results)

		if async_file_dialog_get_results(&ui.dialogs.set_background, &results) {
			bg_path := string_from_array(results[0][:])
			_set_background(ui, bg_path, context.allocator)
		}
	}

	// --------------------------------------------------------------------------
	// Draw background
	// --------------------------------------------------------------------------

	// Re-load background if graphics device was lost
	if ui.background.texture != nil && texture_is_outdated(ui.background.texture.?) {
		_set_background(ui, ui.background.path, context.allocator)
	}

	if ui.background.texture != nil {
		drawlist := imgui.GetBackgroundDrawList()
		
		if tex_ref, ok := texture_get_imgui_ref(ui.background.texture.?); ok {
			size := imgui.GetIO().DisplaySize
			rect := image_fit_clip(ui.background.policy, {{0, 0}, size}, ui.background.size)
			imgui.DrawList_AddImage(drawlist, tex_ref, rect.min, rect.max)
		}
	}
	
	// --------------------------------------------------------------------------
	// Main menu & status bars
	// --------------------------------------------------------------------------
	_main_menu_bar(sv, ui)
	_status_bar(sv, ui)

	// --------------------------------------------------------------------------
	// Debug
	// --------------------------------------------------------------------------
	if ui.debug.show_style_editor {
		if imgui.Begin("[Debug] Style editor", &ui.debug.show_style_editor) {
			imgui.ShowStyleEditor()
		}
		imgui.End()
	}

	if ui.debug.show_demo_window {
		imgui.ShowDemoWindow(&ui.debug.show_demo_window)
	}

	defer if ui.debug.show_memory_tracking {
		if imgui.Begin("[Debug] Memory tracking", &ui.debug.show_memory_tracking) {
			_show_memory_tracking(ui)
		}
		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Show windows
	// --------------------------------------------------------------------------
	for win, id in _WINDOW_INFO {
		name_buf: [512]u8
		state := &ui.window_state[id]

		if state.bring_to_front {
			state.open = true
		}
		
		if !state.open do continue
		if win.show_proc == nil do continue
		fmt.bprintf(name_buf[:511], "%s###%s", win.title, win.internal_name)
		
		if state.bring_to_front {
			state.bring_to_front = false
			imgui.SetNextWindowFocus()
		}

		if imx.begin(cstring(&name_buf[0]), &state.open, win.imgui_flags | state.imgui_flags) {
			win.show_proc(ui)
			imgui.End()
		}
	}

	return ui.actions
}

_main_menu_bar :: proc(sv: ^Server, ui: ^UI) {
	if imgui.BeginMainMenuBar() {
		defer imgui.EndMainMenuBar()

		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Add folders") {
				async_file_dialog_open(&ui.dialogs.add_folder, .Audio, {.SelectFolders, .SelectMultiple})
			}
			if !global_command_opts.no_tray {
				ui.actions.minimize_to_tray |= imgui.MenuItem("Minimize to tray")
			}
			ui.actions.exit |= imgui.MenuItem("Exit")
			imgui.EndMenu()
		}

		if imgui.BeginMenu("Settings") {
			if imgui.MenuItem("Edit settings") {
				ui.window_state[.Settings].bring_to_front = true
			}

			if imgui.MenuItem("Change background") {
				async_file_dialog_open(&ui.dialogs.set_background, .Image, {})
			}

			imgui.EndMenu()
		}

		if imgui.BeginMenu("View") {
			defer imgui.EndMenu()

			category_names := [_Window_Category]cstring {
				.Music = "Music",
				.Visualizers = "Visualizers",
				.Settings = "Settings",
			}

			window_items := [_Window_Category][]_Window_ID {
				.Music = {
					.Albums,
					.Artists,
					.FolderTree,
					.Genres,
					.Library,
					.Playlists,
					.Queue,
				},
				.Visualizers = {
					.Oscilloscope,
					.Spectrum,
					.Wavebar,
				},
				.Settings = {
					.ThemeEditor,
					.PostProcessing
				},
			}

			for section, category in window_items {
				imgui.SeparatorText(category_names[category])
				for id in section {
					info := _WINDOW_INFO[id]
					state := &ui.window_state[id]
					if imgui.MenuItem(info.title) {
						state.bring_to_front = true
					}
				}
			}
		}

		if imgui.BeginMenu("Library") {
			defer imgui.EndMenu()

			if imgui.MenuItem("Update all metadata") {
				server_start_metadata_refresh(sv)
			}

			if imgui.MenuItem("Update cover art") {
				server_start_cover_art_scan(sv)
			}

			if imgui.MenuItem("Remove missing tracks") {
				ui.dialogs.confirm_remove_missing_tracks, _ = 
					show_message_box_async(.YesNo, .Warning, "Remove Missing Tracks", "Remove all tracks with missing files? This cannot be undone.")
			}
		}

		if imgui.BeginMenu("About") {
			defer imgui.EndMenu()

			if imgui.MenuItem("License") {
				ui.window_state[.Licenses].bring_to_front = true
			}
		}

		when ODIN_DEBUG {
			if imgui.BeginMenu("Debug") {
				if imgui.MenuItem("Style editor") {
					ui.debug.show_style_editor = true
				}
				if imgui.MenuItem("Demo window") {
					ui.debug.show_demo_window = true
				}
				if imgui.MenuItem("Show memory tracking") {
					ui.debug.show_memory_tracking = true
				}
				if imgui.MenuItem("Force video reset") {
					ui.actions.debug.force_device_reset = true
				}
				if imgui.MenuItem("Save library") {
					ui.actions.debug.save_library = true
				}
				if imgui.MenuItem("Load library") {
					ui.actions.debug.load_library = true
				}
				if imgui.MenuItem("Test message boxes") {
					show_message_box_async(.Message, .Info, "Info Test", "This is a message")
					show_message_box_async(.YesNo, .Question, "Question Test", "Yes or no?")
					show_message_box_async(.OkCancel, .Warning, "Warning Test", "Ok or cancel?")
					show_message_box_async(.Message, .Error, "Error Test", "Error!")
				}
				imx.select_enum("Background policy", &ui.background.policy)
				imgui.EndMenu()
			}
		}
		// -----------------------------------------------------------------------
		// Volume
		// -----------------------------------------------------------------------
		imgui.Separator()
		volume := audio_get_volume() * 100
		volume_label: cstring = ICON_VOLUME_OFF + "###volume"

		if volume      >= 75 do volume_label = ICON_VOLUME_HIGH + "###volume"
		else if volume >= 50 do volume_label = ICON_VOLUME_MEDIUM + "###volume"
		else if volume >= 1 do volume_label = ICON_VOLUME_LOW + "###volume"

		imgui.SetNextItemWidth(100)
		if imgui.SliderFloat(volume_label, &volume, 0, 100, "%.0f%%") {
			audio_set_volume(volume / 100)
		}

		// -----------------------------------------------------------------------
		// Playback controls
		// -----------------------------------------------------------------------
		imgui.Separator()
		shuffled := server_is_shuffle_enabled(sv)

		if imgui.MenuItem(ICON_STOP) {
			server_request_stop(sv)
		}

		if imgui.MenuItem(
			ICON_SHUFFLE + "###shuffle", nil, shuffled
		) {
			if shuffled {
				server_set_shuffle_enabled(sv, false)
			}
			else {
				server_set_shuffle_enabled(sv, true)
			}
		}

		if imgui.MenuItem(ICON_PREVIOUS_TRACK) {
			server_request_previous_track(sv)
		}
		
		switch sv.playback_state {
		case .Stopped, .Paused:
			if imgui.MenuItem(ICON_PLAY + "###playback_state", enabled=sv.playback_state != .Stopped) {
				server_request_resume(sv)
			}
		case .Playing:
			if imgui.MenuItem(ICON_PAUSE + "###playback_state", enabled=sv.playback_state != .Stopped) {
				server_request_pause(sv)
			}
		}

		if imgui.MenuItem(ICON_NEXT_TRACK) {
			server_request_next_track(sv)
		}

		// -----------------------------------------------------------------------
		// Seek bar
		// -----------------------------------------------------------------------
		imgui.Separator()
		{
			current_pos := server_get_track_position_seconds(sv)
			duration := sv.track_info.duration

			dh, dm, ds := time.clock_from_seconds(auto_cast duration)
			ph, pm, ps := time.clock_from_seconds(auto_cast current_pos)
			imx.textf(32, "%02d:%02d:%02d/%02d:%02d:%02d", ph, pm, ps, dh, dm, ds)

			if imx.scrubber("##seekbar", &current_pos, 0, duration) {
				server_seek(sv, current_pos)
			}
		}
	}
}

_status_bar :: proc(sv: ^Server, ui: ^UI) -> bool {
	imgui.BeginViewportSideBar(
		"##status", imgui.GetMainViewport(), .Down, imgui.GetFrameHeight(), {
			.MenuBar, .NoSavedSettings, .NoScrollbar
		}
	) or_return
	imgui.BeginMenuBar() or_return
	defer imgui.End()
	defer imgui.EndMenuBar()

	// --------------------------------------------------------------------------
	// Track info
	// --------------------------------------------------------------------------
	if track, have_track := get_track(sv, sv.current_track_id); have_track {
		artists := library_join_track_group_names_to_allocator(
			sv.library, track.artists, .Artist, ui.allocators.per_frame
		)

		imx.text(512, artists, " - ", track.title)
		imgui.Separator()
		track_info := sv.track_info

		imx.text_unformatted_ex(track.album != 0 ? get_album_name(sv^, track.album) : "<no album>")

		imgui.Separator()
		if channel_string, have_channel_string := audio_channels_to_string(
			auto_cast track.channels
		); have_channel_string {
			imx.text_unformatted(channel_string)
		}
		else {
			imx.text(32, track.channels, " channels")
		}

		imgui.Separator()
		imx.text(32, AUDIO_FILE_FORMAT_DISPLAY_NAMES[track.format].long)
		imgui.Separator()
		imx.text(32, track.samplerate, "Hz")
		imgui.Separator()
		imx.text(32, track.bitrate_kbps, "kb/s")
		imgui.Separator()

		if track_info.replay_gain != nil {
			rp := track_info.replay_gain.?
			imx.textf(64, "Applied gain: %.2fdB", rp.track_gain)
			imgui.Separator()
			imx.textf(64, "Peak: %.2fdB", rp.track_peak)
			imgui.Separator()
		}
	}

	// --------------------------------------------------------------------------
	// Metadata scan progress
	// --------------------------------------------------------------------------
	if scanned_dirs, total_dirs, scanned_files, scanning := track_scanner_get_progress(
		&sv.track_scanner
	); scanning {
		progress := f32(scanned_dirs) / f32(total_dirs)
		imgui.ProgressBar(progress, {100, 0})
		imx.textf(64, "Scanning metadata (%d/%d) (%d)", scanned_dirs, total_dirs, scanned_files)
		imgui.Separator()
	}

	// --------------------------------------------------------------------------
	// Cover art scan progress
	// --------------------------------------------------------------------------
	if scanned, total, running := bgtask_get_progress(&sv.cover_art_scan); running {
		progress := f32(scanned) / f32(total)
		imgui.ProgressBar(progress, {100, 0})
		imx.textf(64, "Scanning cover art (%d/%d)", scanned, total)

		imgui.Separator()
	}

	return true
}

// -----------------------------------------------------------------------------
// Track table
// -----------------------------------------------------------------------------

_track_table_row_from_track :: proc(
	sv: ^Server, handle: Track_ID, allocator: mem.Allocator,
) -> (row: _Track_Table_Row, ok: bool) {
	track := get_track(sv, handle) or_return
	ok = true

	row.id = handle
	row.album = track.album
	row.artists = track.artists
	row.genres = track.genres
	row.title = track.title
	row.url = track.url

	{
		h, m, s := time.clock_from_seconds(auto_cast track.duration_seconds)
		fmt.bprintf(row.duration[:], "%02d:%02d:%02d", h, m, s)
	}

	if track.track_no != 0 do fmt.bprint(row.track_no[:], track.track_no)
	fmt.bprint(row.year[:], track.release_year)

	fmt.bprint(row.samplerate[:], track.samplerate, "Hz", sep="")
	fmt.bprint(row.bitrate[:], track.bitrate_kbps, "kb/s", sep="")
	row.format = track.format

	return
}

_track_table_get_tracks :: proc(t: _Track_Table, allocator: mem.Allocator) -> []Track_ID {
	out := make([]Track_ID, len(t.rows), allocator)
	for row, i in t.rows {
		out[i] = row.id
	}

	return out
}

_track_table_get_selection :: proc(t: _Track_Table, allocator: mem.Allocator) -> []Track_ID {
	out: [dynamic]Track_ID
	for row in t.rows {
		if row.selected do append(&out, row.id)
	}
	return out[:]
}

_Track_Table_Flag :: enum {IsQueue, NoRemove}

_track_table_show :: proc(
	ui: ^UI,
	name: cstring,
	table: ^_Track_Table,
	serial: uint,
	track_ids: []Track_ID,
	flags: bit_set[_Track_Table_Flag],
	playlist_id: UID,
) -> bool {
	sv := ui.server

	filter_spec := Track_Filter_Spec {
		metrics = ~{.Url, .Format},
		filter_string = string(cstring(&table.filter_buf[0])),
	}

	filter_hash := stable_hash_string_32(filter_spec.filter_string)

	// --------------------------------------------------------------------------
	// Update if needed
	// --------------------------------------------------------------------------
	if serial != table.serial || table.playlist_uid != playlist_id || filter_hash != table.filter_hash {
		TIME_SCOPE("Build track table", name)

		if table.scratch.data == nil {
			mem.scratch_init(&table.scratch, 64<<10)
		}

		scratch := mem.scratch_allocator(&table.scratch)
		mem.scratch_free_all(&table.scratch)

		filtered_tracks: []Track_ID
		table.filter_hash = stable_hash_string_32(filter_spec.filter_string)

		if table.filter_buf[0] == 0 {
			filtered_tracks = track_ids
		}
		else {
			buf := make_dynamic_array_len_cap([dynamic]Track_ID, 0, len(track_ids), ui.allocators.per_frame)
			filter_tracks(sv.library, &buf, track_ids, filter_spec)
			filtered_tracks = buf[:]
		}

		table.serial = serial
		table.playlist_uid = playlist_id
		clear(&table.rows)

		for track in filtered_tracks {
			row := _track_table_row_from_track(sv, track, scratch) or_continue
			append(&table.rows, row)
		}

		if table.sort_spec != nil {
			_sort_track_table_rows(ui, table, table.sort_spec.?)
		}
	}

	// --------------------------------------------------------------------------
	// Filter
	// --------------------------------------------------------------------------
	imgui.SetNextItemWidth(500)
	if _is_key_chord_pressed_in_window(.ImGuiMod_Ctrl, .F) {
		imgui.SetKeyboardFocusHere()
	}
	imgui.InputTextWithHint("##filter", "Filter", cstring(&table.filter_buf[0]), auto_cast len(table.filter_buf))

	// --------------------------------------------------------------------------
	// Show
	// --------------------------------------------------------------------------

	imgui.TextDisabled("%d tracks", i32(len(table.rows)))

	_Column_Index :: enum {
		TrackNo,
		Title,
		Artist,
		Album,
		Genre,
		Duration,
		Bitrate,
		Format,
		Samplerate,
	}

	actions: struct {
		play_track: Maybe(Track_ID),
		add_to_playlist: Maybe(Playlist_Handle),
		play_selection: bool,
		context_menu_target: Track_ID,
		play_similar_tracks: bool,
		go_to_artist: Artist_ID,
		go_to_album: Album_ID,
		go_to_genre: Genre_ID,
		add_selection_to_queue: bool,
	}

	list_clipper: imgui.ListClipper

	_check_table_size() or_return
	imgui.BeginTable(name, auto_cast len(_Column_Index),
		imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Hideable|imgui.TableFlags_Reorderable|
		imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Sortable|
		imgui.TableFlags_ScrollX
	) or_return
	defer imgui.EndTable()

	// --------------------------------------------------------------------------
	// Columns
	// --------------------------------------------------------------------------
	column_infos: [_Column_Index]struct {
		name: cstring,
		sort_metric: Track_Sort_Metric,
		flags: imgui.TableColumnFlags,
	} = {
		.Title =      {"Title",       .Title,      {.NoHide},    },
		.Artist =     {"Artist",      .Artist,     {},           },
		.Album =      {"Album",       .Album,      {},           },
		.Genre =      {"Genre",       .Genre,      {.DefaultHide}},
		.TrackNo =    {"Track",       .Track,      {.DefaultHide}},
		.Duration =   {"Duration",    .Duration,   {},           },
		.Bitrate =    {"Bitrate",     .Bitrate,    {.DefaultHide}},
		.Format =     {"Format",      .Format,     {.DefaultHide}},
		.Samplerate = {"Sample Rate", .Samplerate, {.DefaultHide}},
	}

	// --------------------------------------------------------------------------
	// Display table
	// --------------------------------------------------------------------------
	for col in column_infos {
		imgui.TableSetupColumn(col.name, col.flags, 1.0/f32(len(_Column_Index)))
	}

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	// --------------------------------------------------------------------------
	// Sort
	// --------------------------------------------------------------------------
	if table_sort_specs := imgui.TableGetSortSpecs(); table_sort_specs != nil {
		if specs := table_sort_specs.Specs; specs != nil && table_sort_specs.SpecsDirty {
			table_sort_specs.SpecsDirty = false

			column := cast(_Column_Index) specs.ColumnIndex
			switch specs.SortDirection {
			case .None:
				table.sort_spec = nil
			case .Ascending:
				table.sort_spec = Track_Sort_Spec {
					metric = column_infos[column].sort_metric,
					order = .Ascending,
				}
			case .Descending:
				table.sort_spec = Track_Sort_Spec {
					metric = column_infos[column].sort_metric,
					order = .Descending
				}
			}

			if table.sort_spec != nil {
				_sort_track_table_rows(ui, table, table.sort_spec.?)
				log.debug("Sorting track table", name, "with by", table.sort_spec.?.metric)
			}
		}
	}

	string_builder: strings.Builder
	strings.builder_init(&string_builder, ui.allocators.per_frame)

	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows), imgui.GetTextLineHeightWithSpacing())
	defer imgui.ListClipper_End(&list_clipper)

	for imgui.ListClipper_Step(&list_clipper) {
		for &row, local_row_index in table.rows[list_clipper.DisplayStart:list_clipper.DisplayEnd] {
			imgui.TableNextRow()
			row_index := local_row_index + auto_cast list_clipper.DisplayStart
			imgui.PushIDInt(auto_cast row_index)
			defer imgui.PopID()

			// --------------------------------------------------------------------
			// Title
			// --------------------------------------------------------------------
			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Title) {
				title_buf: [128]u8
				copy(title_buf[:127], row.title)

				if row.id == sv.current_track_id {
					imgui.TableSetBgColor(.RowBg0, ui_theme.colors[.PlayingHighlight])
				}

				if imgui.Selectable(cstring(&title_buf[0]), row.selected, {.SpanAllColumns}) {
					_table_select_row(table, row_index, false)
				}

				if imgui.BeginItemTooltip() {
					if track, got_track := get_track(sv, row.id); got_track {
						_show_track_metadata_table(ui, "##metadata", sv^, track)
					}
					imgui.EndTooltip()
				}

				if imgui.IsItemClicked(.Middle) || imx.is_item_double_clicked() {
					actions.play_track = row.id
				}

				// -----------------------------------------------------------------
				// Context menu
				// -----------------------------------------------------------------
				if imgui.BeginPopupContextItem() {
					defer imgui.EndPopup()

					actions.context_menu_target = row.id

					_table_select_row(table, row_index, true)


					if add_to_playlist, yes := _show_playlist_selector_menu(sv, "Add to playlist"); yes {
						actions.add_to_playlist = add_to_playlist
					}

					if imgui.MenuItem("Play selection") {
						actions.play_selection = true
					}

					if imgui.MenuItem("Play similar tracks") {
						actions.play_similar_tracks = true
					}

					if imgui.BeginMenu("More by...") {
						defer imgui.EndMenu()

						for artist in row.artists {
							if artist == 0 do break
							name := library_get_artist_name(sv.library, artist)
							if imgui.MenuItem(strings.clone_to_cstring(name, ui.allocators.per_frame)) {
								actions.go_to_artist = artist
							}
						}
					}

					if imgui.MenuItem("Add to queue") {
						actions.add_selection_to_queue = true
					}

					imgui.Separator()
					//@FIXME
					/*if row.artist != 0 && imgui.MenuItem("More by this artist...") {
						actions.go_to_artist = row.artist
					}*/

					if row.album != 0 && imgui.MenuItem("View album") {
						actions.go_to_album = row.album
					}

					if imgui.BeginMenu("More in genre...") {
						defer imgui.EndMenu()

						for genre in row.genres {
							if genre == 0 do break
							name := library_get_genre_name(sv.library, genre)
							if imgui.MenuItem(strings.clone_to_cstring(name, ui.allocators.per_frame)) {
								actions.go_to_genre = genre
							}
						}
					}


					if .NoRemove not_in flags {
						imgui.Separator()
						imgui.MenuItem("Remove")
					}
				}

			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Artist) {
				strings.builder_reset(&string_builder)
				imx.text_unformatted(
					library_join_track_group_names_to_builder(sv.library, &string_builder, row.artists, .Artist)
				)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Album) {
				imx.text_unformatted(get_album_name(sv^, row.album))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Genre) {
				strings.builder_reset(&string_builder)
				imx.text_unformatted(
					library_join_track_group_names_to_builder(sv.library, &string_builder, row.genres, .Genre)
				)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Duration) {
				imx.text_unformatted(string_from_array(row.duration[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.TrackNo) {
				imx.text_unformatted(string_from_array(row.track_no[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Format) {
				imx.text_unformatted(AUDIO_FILE_FORMAT_DISPLAY_NAMES[row.format].long)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Bitrate) {
				imx.text_unformatted(string_from_array(row.bitrate[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Samplerate) {
				imx.text_unformatted(string_from_array(row.samplerate[:]))
			}
		}
	}
	
	// --------------------------------------------------------------------------
	// Process actions
	// --------------------------------------------------------------------------
	if actions.play_track != nil {
		if .IsQueue in flags {
			server_move_queue_to_track(sv, actions.play_track.?)
		}
		else {
			tracks := _track_table_get_tracks(table^, ui.allocators.per_frame)
			server_request_play_playlist(sv, tracks, playlist_id, actions.play_track.?)
		}
	}

	if actions.play_selection {
		sel := _track_table_get_selection(table^, ui.allocators.per_frame)
		server_request_play_playlist(sv, sel, table.playlist_uid)
	}

	if actions.add_to_playlist != nil {
		h := actions.add_to_playlist.?
		if playlist, ok := library_get_playlist(&sv.library, h); ok {
			playlist_add(sv, playlist, _track_table_get_selection(table^, ui.allocators.per_frame))
		}
	}

	if actions.play_similar_tracks {
		server_request_radio(sv, actions.context_menu_target)
	}

	if actions.add_selection_to_queue {
		sel := _track_table_get_selection(table^, ui.allocators.per_frame)
		playback_queue_add(&sv.playback, sel, table.playlist_uid)
	}

	if actions.go_to_genre != 0 do _go_to_genre(ui, actions.go_to_genre)
	if actions.go_to_album != 0 do _go_to_album(ui, actions.go_to_album)
	if actions.go_to_artist != 0 do _go_to_artist(ui, actions.go_to_artist)

	return true
}

_sort_track_table_rows :: proc(ui: ^UI, table: ^_Track_Table, spec: Track_Sort_Spec) {
	sv := ui.server
	tracks := _track_table_get_tracks(table^, ui.allocators.per_frame)

	sort_tracks(sv, tracks, spec)

	for track_id, i in tracks {
		row := _track_table_row_from_track(sv, track_id, mem.scratch_allocator(&table.scratch)) or_continue
		table.rows[i] = row
	}
}

// -----------------------------------------------------------------------------
// Metadata window
// -----------------------------------------------------------------------------

_show_track_metadata_table :: proc(ui: ^UI, str_id: cstring, sv: Server, track: Track) -> bool {
	imx.begin_kv_table(str_id, imgui.TableFlags_RowBg) or_return
	defer imx.end_kv_table()

	protocol_string := [Track_Protocol]string {
		.File = "Disk"
	}

	imgui.TableSetupColumn("name", {.WidthStretch}, 0.2)
	imgui.TableSetupColumn("value", {.WidthStretch}, 0.8)
	
	if track.title != "" do imx.kv_row("Title", track.title)

	//@FIXME
	/*if track.artist != 0 && imx.kv_row("Artist", get_artist_name(sv, track.artist)) {
		_go_to_artist(ui, track.artist)
	}*/

	imx.kv_row("Artist(s)", library_join_track_group_names_to_allocator(sv.library, track.artists, .Artist, ui.allocators.per_frame))
	
	if track.album != 0 && imx.kv_row("Album", get_album_name(sv, track.album)) {
		_go_to_album(ui, track.album)
	}
	
	imx.kv_row("Genre(s)", library_join_track_group_names_to_allocator(sv.library, track.genres, .Genre, ui.allocators.per_frame))

	//@FIXME
	/*if track.genre != 0 && imx.kv_row("Genre", get_genre_name(sv, track.genre)) {
		_go_to_genre(ui, track.genre)
	}*/

	imx.kv_rowf("Duration", "%02d:%02d:%02d", time.clock_from_seconds(auto_cast track.duration_seconds))
	imx.kv_row("Format", AUDIO_FILE_FORMAT_DISPLAY_NAMES[track.format].long)
	if track.samplerate != 0 do imx.kv_row("Sample rate", track.samplerate, "Hz", sep="")
	if track.url != "" do imx.kv_row("Path", track.url)
	imx.kv_row("From", protocol_string[track.protocol])

	if track.protocol == .File {
		imx.kv_rowf("File size", "%M", track.file_size)
	}

	return true
}

_metadata_window_show :: proc(ui: ^UI, w: ^_Metadata_Window, track_id: Track_ID) -> bool {
	sv := ui.server

	load_cover :: proc(sv: ^Server, w: ^_Metadata_Window) -> bool {
		if w.cover_art != nil {
			texture_release(w.cover_art.?)
			w.cover_art = nil
		}

		cover_data, mime_type := find_track_thumbnail(
			sv.library, w.displayed_track, context.allocator
		) or_return

		delete(mime_type)
		defer delete(cover_data)

		h, width, height := texture_create_from_memory(cover_data) or_return
		w.cover_art = h
		w.cover_width = width
		w.cover_height = height
		w.cover_file_size = len(cover_data)

		return true
	}

	if w.displayed_track != track_id {
		w.displayed_track = track_id

		if w.displayed_track == {} {
			imgui.TextDisabled("No track to display")
			return true
		}
		
		load_cover(sv, w)
	}

	if w.displayed_track == {} {
		imgui.TextDisabled("No track to display")
		return true
	}

	md := get_track(sv, w.displayed_track) or_return

	// Update cover art if needed
	if w.cover_art != nil && texture_is_outdated(w.cover_art.?) {
		w.cover_art = nil
		load_cover(sv, w)
	}
	
	avail_size := imgui.GetContentRegionAvail()

	// Cover art
	if w.cover_art != nil {
		if ref, ok := texture_get_imgui_ref(w.cover_art.?); ok {
			imgui.PushStyleColor(.Button, 0)
			imgui.PushStyleColor(.ButtonHovered, 0)
			imgui.PushStyleColor(.ButtonActive, 0)
			defer imgui.PopStyleColor(3)

			if global_config.ui.crop_cover_art {
				uv := image_fit_uv(.Fill, {{}, avail_size.xx}, {f32(w.cover_width), f32(w.cover_height)})
				imgui.ImageButton("##cover", ref, avail_size.xx, uv.min, uv.max)
			}
			else {
				ratio := f32(w.cover_height) / f32(w.cover_width)
				imgui.ImageButton("##cover", ref, avail_size.xx * {1, ratio})
			}

			if imgui.BeginItemTooltip() {
				imx.text(32, "Dimensions: ", w.cover_width, "x", w.cover_height, sep="")
				imx.textf(32, "Size: %M", w.cover_file_size)
				imgui.EndTooltip()
			}

			if imgui.BeginPopupContextItem("##cover") {
				defer imgui.EndPopup()
				if imgui.MenuItem("Crop to square", nil, global_config.ui.crop_cover_art) {
					global_config.ui.crop_cover_art = !global_config.ui.crop_cover_art
					global_config_dirty = true
				}
			}
		}
	}

	imx.push_font_scale(1.2)
	imgui.SeparatorText("Metadata")
	imgui.PopFont()
	_show_track_metadata_table(ui, "##metadata", sv^, md)

	return true
}

// -----------------------------------------------------------------------------
// Track group table
// -----------------------------------------------------------------------------

_track_group_window_show_groups :: proc(
	ui: ^UI, w: ^_Track_Group_Window, group_type: Track_Group_Type,
) -> (shown: bool) {
	entry: ^Track_Group

	sv := ui.server
	entry_index, have_entry := w.displayed_entry_id.?
	list := &sv.library.track_common_strings[group_type]

	if have_entry do entry = &list.entries[entry_index]

	imgui.SetNextItemWidth(500)
	if _is_key_chord_pressed_in_window(.ImGuiMod_Ctrl, .F) {
		imgui.SetKeyboardFocusHere()
	}
	imgui.InputTextWithHint("##filter", "Filter", cstring(&w.filter_buf[0]), auto_cast len(w.filter_buf))
	filter_string := string(cstring(&w.filter_buf[0]))
	filter_hash := stable_hash_string_32(filter_string)

	// --------------------------------------------------------------------------
	// Rebuild playlist table
	// --------------------------------------------------------------------------
	if w.playlist_table.serial != list.serial || w.filter_hash != filter_hash {
		clear(&w.playlist_table.rows)
		w.playlist_table.serial = list.serial
		w.filter_hash = filter_hash
		
		if w.filter_buf[0] == 0 {
			for e, i in list.entries {
				row := _make_playlist_row(sv.library, e.uid, e.name, e.serial, e.totals)
				row.id = i64(i)
				append(&w.playlist_table.rows, row)
			}
		}
		else {
			lower_filter := strings.to_lower(filter_string, ui.allocators.per_frame)
			for e, i in list.entries {
				if strings.contains(e.lower_case_name, lower_filter) {
					row := _make_playlist_row(sv.library, e.uid, e.name, e.serial, e.totals)
					row.id = i64(i)
					append(&w.playlist_table.rows, row)
				}
			}
		}

		_playlist_table_sort(&w.playlist_table)
	}

	imx.title_text(string(_TRACK_COMMON_STRING_TYPE_NAMES[group_type]))

	result, _ := _playlist_table_show("##playlists", sv, &w.playlist_table, {})
	if result.selected_row != nil {
		row := w.playlist_table.rows[result.selected_row.?]
		_track_group_window_select_group(ui, w, group_type, auto_cast row.id)
	}

	if result.played_row != nil {
		row := w.playlist_table.rows[result.played_row.?]
		_track_group_window_select_group(ui, w, group_type, auto_cast row.id)
		server_request_play_playlist(sv, w.tracks[:], row.uid)
	}

	return true
}

_track_group_window_show_tracks :: proc(
	ui: ^UI, w: ^_Track_Group_Window, group_type: Track_Group_Type
) -> bool {
	entry: ^Track_Group

	sv := ui.server
	entry_index, have_entry := w.displayed_entry_id.?
	list := sv.library.track_common_strings[group_type]

	if have_entry do entry = &list.entries[entry_index]
	else {
		if w.displayed_entry_id != nil do w.displayed_entry_id = nil
		imgui.TextDisabled("Select a playlist")
		return false
	}

	if entry.name == "" {
		imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
		imx.title_text(_TRACK_COMMON_STRING_TYPE_NAMES[group_type], ": None", sep="")
		imgui.PopStyleColor()
	}
	else {
		imx.title_text(_TRACK_COMMON_STRING_TYPE_NAMES[group_type], ": ", entry.name, sep="")
	}

	_track_table_show(
		ui, "##tracks", &w.track_table, list.serial,
		w.tracks[:], {.NoRemove}, entry.uid
	)

	return true
}

_track_group_window_show_focused :: proc(
	ui: ^UI, w: ^_Track_Group_Window, group_type: Track_Group_Type,
) {
	if w.displayed_entry_id != nil {
		if imgui.Button("Back") {
			w.displayed_entry_id = nil
		}
		_track_group_window_show_tracks(ui, w, group_type)
	}
	else {
		_track_group_window_show_groups(ui, w, group_type)
	}
}

_track_group_window_select_group :: proc(
	ui: ^UI, w: ^_Track_Group_Window, group_type: Track_Group_Type, id: Track_Group_ID
) {
	w.displayed_entry_id = i16(id)
	clear(&w.tracks)
	library_get_tracks_in_group(ui.server.library, group_type, id, &w.tracks)
}

// -----------------------------------------------------------------------------
// Playlist table
// -----------------------------------------------------------------------------

_Playlist_Table_Row :: struct {
	uid: UID,
	id: i64,
	title: string,
	file_size: [12]u8,
	duration: [9]u8,
	length: [8]u8,
	selected: bool,
	serial: uint,
	totals: Track_List_Totals,
}

_Playlist_Compare_Proc :: #type proc(a, b: _Playlist_Table_Row) -> int

_Playlist_Sort_Metric :: enum {Name, Length, Duration, FileSize}

_PLAYLIST_SORT_METRIC_PROCS := [_Playlist_Sort_Metric]_Playlist_Compare_Proc {
	.Name = proc(a, b: _Playlist_Table_Row) -> int {return strings.compare(a.title, b.title)},
	.Length = proc(a, b: _Playlist_Table_Row) -> int {return auto_cast (a.totals.track_count - b.totals.track_count)},
	.Duration = proc(a, b: _Playlist_Table_Row) -> int {return auto_cast (a.totals.duration - b.totals.duration)},
	.FileSize = proc(a, b: _Playlist_Table_Row) -> int {return auto_cast (a.totals.file_size - b.totals.file_size)}
}

_Playlist_Sort_Spec :: struct {
	metric: _Playlist_Sort_Metric,
	order: Sort_Order,
}

_Playlist_Table :: struct {
	serial: uint,
	rows: [dynamic]_Playlist_Table_Row,
	sort_spec: Maybe(_Playlist_Sort_Spec),
}

_Playlist_Table_Actions :: struct {
	selected_row: Maybe(int),
	played_row: Maybe(int),
	remove_row: Maybe(int),
}

_Playlist_Table_Flag :: enum {MultiSelect}
_Playlist_Table_Flags :: bit_set[_Playlist_Table_Flag]

_Playlist_Table_Context_Item :: enum {Remove}
_Playlist_Table_Context_Items :: bit_set[_Playlist_Table_Context_Item]

_playlist_table_sort :: proc(
	table: ^_Playlist_Table
) {
	if table.sort_spec == nil do return

	spec := table.sort_spec.?

	iface := sort.Interface {
		collection = table,
		len = proc(it: sort.Interface) -> int {
			table := cast(^_Playlist_Table) it.collection
			return len(table.rows)
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			table := cast(^_Playlist_Table) it.collection
			cmp := _PLAYLIST_SORT_METRIC_PROCS[table.sort_spec.?.metric]
			return cmp(table.rows[a], table.rows[b]) < 0
		},
		swap = proc(it: sort.Interface, a, b: int) {
			table := cast(^_Playlist_Table) it.collection
			table.rows[a], table.rows[b] = table.rows[b], table.rows[a]
		},
	}

	if spec.order == .Ascending do sort.sort(iface)
	else do sort.reverse_sort(iface)
}

_playlist_table_show :: proc(
	str_id: cstring, sv: ^Server, table: ^_Playlist_Table,
	flags: _Playlist_Table_Flags, context_items: _Playlist_Table_Context_Items = {},
) -> (result: _Playlist_Table_Actions, shown: bool) {
	actions: struct {
		play: Maybe(int),
		play_selection: bool,
	}

	_check_table_size() or_return
	imgui.BeginTable(
		str_id, 4,
		imgui.TableFlags_BordersInner|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Reorderable|
		imgui.TableFlags_ScrollX|imgui.TableFlags_ScrollY|imgui.TableFlags_Sortable|
		imgui.TableFlags_RowBg
	) or_return
	defer imgui.EndTable()

	imgui.TableSetupColumn("Name")
	imgui.TableSetupColumn("Duration")
	imgui.TableSetupColumn("Length")
	imgui.TableSetupColumn("Total File Size")

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	if table_ss := imgui.TableGetSortSpecs(); table_ss != nil {
		if ss := table_ss.Specs; ss != nil && table_ss.SpecsDirty {
			if ss.SortDirection == .None {
				table.sort_spec = nil
			}
			else {
				spec := _Playlist_Sort_Spec{}
				switch ss.ColumnIndex {
				case 0: spec.metric = .Name
				case 1: spec.metric = .Duration
				case 2: spec.metric = .Length
				case 3: spec.metric = .FileSize
				}

				switch ss.SortDirection {
				case .None: 
				case .Ascending: spec.order = .Ascending
				case .Descending: spec.order = .Descending
				}
				
				table.sort_spec = spec
				_playlist_table_sort(table)
			}
		}
	}

	list_clipper: imgui.ListClipper
	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows), imgui.GetTextLineHeightWithSpacing())
	defer imgui.ListClipper_End(&list_clipper)

	for imgui.ListClipper_Step(&list_clipper) {
		for &row, local_row_index in table.rows[list_clipper.DisplayStart:list_clipper.DisplayEnd] {
			imgui.TableNextRow()
			row_index := local_row_index + auto_cast list_clipper.DisplayStart
			imgui.PushIDInt(auto_cast row_index)
			defer imgui.PopID()

			if row.uid == sv.playback.playlist_uid {
				imgui.TableSetBgColor(.RowBg0, ui_theme.colors[.PlayingHighlight])
			}

			if imgui.TableSetColumnIndex(0) {
				buf: [256]u8
				if row.title == "" do copy(buf[:255], "<None>")
				else do copy(buf[:255], row.title)

				if row.title == "" do imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
				
				if imgui.Selectable(cstring(&buf[0]), row.selected, {.SpanAllColumns}) {
					if .MultiSelect in flags {
						_table_select_row(table, row_index, false)
					}
					else {
						result.selected_row = row_index
						for &other_row in table.rows do other_row.selected = false
						row.selected = true
					}
				}

				if row.title == "" do imgui.PopStyleColor()
				
				if imgui.IsItemClicked(.Middle) {
					actions.play = row_index
				}

				if context_items != {} && imgui.BeginPopupContextItem() {
					defer imgui.EndPopup()

					if .Remove in context_items && imgui.MenuItem("Remove") {
						result.remove_row = row_index
					}
				}
			}

			if imgui.TableSetColumnIndex(1) {
				imx.text_unformatted(string_from_array(row.duration[:]))
			}

			if imgui.TableSetColumnIndex(2) {
				imx.text_unformatted(string_from_array(row.length[:]))
			}

			if imgui.TableSetColumnIndex(3) {
				imx.text_unformatted(string_from_array(row.file_size[:]))
			}
		}
	}

	if actions.play != nil {
		row := table.rows[actions.play.?]
		result.played_row = actions.play.?
	}

	shown = true
	return
}

_make_playlist_row :: proc(
	l:      Library,
	uid:    UID,
	title:  string,
	serial: uint,
	totals: Track_List_Totals,
	id:     i64 = 0,
) -> _Playlist_Table_Row {
	row := _Playlist_Table_Row {
		uid    = uid,
		serial = serial,
		title  = title,
		totals = totals,
		id     = id,
	}

	format_duration(row.duration[:], auto_cast row.totals.duration)
	fmt.bprint(row.length[:], row.totals.track_count)
	fmt.bprintf(row.file_size[:], "%M", row.totals.file_size)

	return row
}

// -----------------------------------------------------------------------------
// Themes
// -----------------------------------------------------------------------------

_theme_editor_show :: proc(ui: ^UI) -> (changed: bool) {
	accent_changed: bool

	t := &ui_theme
	colors := &t.imgui_colors

	defer if changed {
		imgui.GetStyle().Colors = t.imgui_colors
	}

	// Load/save
	{
		imgui.BeginDisabled(t.name[0] == 0)
		defer imgui.EndDisabled()

		if imgui.Button("Save") {
			if t.path == "" {
				buf: [64]u8
				id := rand.uint64()
				file_name := fmt.bprint(buf[:], id, ".json", sep="")
				path, _ := os.join_path({ui.paths.theme_folder, file_name}, ui.allocators.per_frame)

				for os.exists(path) {
					id = rand.uint64()
					file_name = fmt.bprint(buf[:], id, ".json", sep="")
					path, _ = os.join_path({ui.paths.theme_folder, file_name}, ui.allocators.per_frame)
				}

				t.path = strings.clone(path, ui.allocators.themes)
			}

			_save_theme_to_file(t.path)
			_load_themes(ui)
		}

		if t.name[0] == 0 {
			imx.set_item_tooltip("Theme must have a name")
		}
	}

	if t.path != "" {
		imgui.SameLine()
		if imgui.Button("Load") {
			t^, _ = _load_theme_from_file(ui, t.path, ui.allocators.themes)
			changed = true
		}

		imgui.SameLine()
		if imgui.Button("New") {
			for &b in t.name do b = 0
			t.path = ""
		}
	}

	if imgui.BeginCombo("##load_existing", nil, {.NoPreview}) {
		defer imgui.EndCombo()
		for &theme, i in ui.themes {
			imgui.PushIDInt(auto_cast i)
			defer imgui.PopID()
			if imgui.MenuItem(cstring(&theme.name[0])) {
				t^ = theme
				changed = true
			}
		}
	}
	imgui.SameLine()
	imgui.InputText("Name", cstring(&t.name[0]), auto_cast len(t.name))

	imgui.BeginTabBar("##theme_tabs") or_return
	defer imgui.EndTabBar()

	edit_accent :: proc(t: ^_Theme, label: cstring, accent: _Theme_Accent) -> (active: bool) {
		imgui.PushIDInt(auto_cast accent)
		defer imgui.PopID()

		active |= imgui.ColorEdit3(label, &t.accents[accent])
		imgui.SameLine()
		if imgui.Button("Random") {
			active = true
			t.accents[accent].rgb = {
				rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1)
			}
		}

		return
	}


	imgui.SeparatorText("Quick edit")
	imgui.PushID("##quick_edit")
	accent_changed |= imgui.Button("Re-apply accent colors")
	accent_changed |= edit_accent(t, "Fg. primary", .Fg1)
	accent_changed |= edit_accent(t, "Fg. secondary", .Fg2)

	changed |= imgui.ColorEdit4("Text", &colors[imgui.Col.Text])
	changed |= imgui.ColorEdit4("Window bg.", &colors[imgui.Col.WindowBg])
	changed |= imgui.ColorEdit4("Menu bar", &colors[imgui.Col.MenuBarBg])
	changed |= imgui.ColorEdit4("Table headers", &colors[imgui.Col.TableHeaderBg])
	imgui.PopID()

	imgui.SeparatorText("RAT MP colors")
	imgui.PushID("##ratmp_colors")
	imx.color_edit_u32("Playing highlight", &t.colors[.PlayingHighlight])
	imx.color_edit_u32("Quiet", &t.colors[.VolumeLow])
	imx.color_edit_u32("Loud", &t.colors[.VolumeHigh])
	imx.color_edit_u32("Left channel wave", &t.colors[.LeftChannelWave])
	imx.color_edit_u32("Right channel wave", &t.colors[.RightChannelWave])
	imx.color_edit_u32("Wavebar quiet", &t.colors[.WaveBarInner])
	imx.color_edit_u32("Wavebar loud", &t.colors[.WaveBarOuter])
	imgui.PopID()

	imgui.SeparatorText("ImGui colors")
	imgui.PushID("##imgui_colors")
	for col in imgui.Col {
		if col == .COUNT do break
		changed |= imgui.ColorEdit4(imgui.GetStyleColorName(col), &colors[col])
	}
	imgui.PopID()

	/*if imgui.BeginTabItem("Sizes") {
		defer imgui.EndTabItem()

		changed |= imgui.SliderFloat2("Cell padding", &style.CellPadding, 0, 16, "%0.f")
		changed |= imgui.SliderFloat("Child border size", &style.ChildBorderSize, 0, 2, "%.0f")
		changed |= imgui.SliderFloat("Child rounding", &style.ChildRounding, 0, 12, "%0.f")
		changed |= imgui.SliderFloat("Frame border size", &style.FrameBorderSize, 0, 1, "%.0f")
		changed |= imgui.SliderFloat2("Frame padding", &style.FramePadding, 0, 16, "%0.f")
		changed |= imgui.SliderFloat("Frame rounding", &style.FrameRounding, 0, 12, "%0.f")
		changed |= imgui.SliderFloat("Image rounding", &style.ImageRounding, 0, 12, "%0.f")
		changed |= imgui.SliderFloat("Tab bar border size", &style.TabBarBorderSize, 0, 1, "%.0f")
		changed |= imgui.SliderFloat("Tab border size", &style.TabBorderSize, 0, 1, "%.0f")
		changed |= imgui.SliderFloat("Tab rounding", &style.TabRounding, 0, 12, "%0.f")
		changed |= imgui.SliderFloat("Window border size", &style.WindowBorderSize, 0, 2, "%0.f")
		changed |= imgui.SliderFloat2("Window padding", &style.WindowPadding, 0, 16, "%0.f")
		changed |= imgui.SliderFloat("Window rounding", &style.WindowRounding, 0, 12, "%0.f")
	}*/

	if accent_changed {
		rgb_to_hsv :: proc(v: [3]f32) -> (hsv: [3]f32) {
			imgui.ColorConvertRGBtoHSV(v.r, v.g, v.b, &hsv[0], &hsv[1], &hsv[2])
			return
		}

		hsv_to_rgb :: proc(v: [3]f32) -> (rgb: [3]f32) {
			imgui.ColorConvertHSVtoRGB(v[0], v[1], v[2], &rgb.r, &rgb.g, &rgb.b)
			return
		}

		changed = true
		_Accent_Color :: struct {
			base: Maybe(_Theme_Accent),
			hsv: [3]f32,
		}

		@static color_map: [imgui.Col]_Accent_Color = #partial {
			.Button = {.Fg1, {1, 1, 1}},
			.ButtonHovered = {.Fg1, {1, 0.9, 1}},
			.ButtonActive = {.Fg1, {1, 1.2, 0.9}},
			.FrameBg = {.Fg1, {1, 0.8, 0.5}},
			.FrameBgHovered = {.Fg1, {1, 0.6, 0.9}},
			.FrameBgActive = {.Fg1, {1, 0.6, 0.9}},
			.Header = {.Fg1, {1, 0.9, 0.9}},
			.HeaderHovered = {.Fg1, {1, 0.8, 1.1}},
			.HeaderActive = {.Fg1, {1, 0.8, 1.0}},
			.TabHovered = {.Fg1, {1, 0.8, 0.8}},
			.Tab = {.Fg1, {1, 0.6, 0.5}},
			.TabSelected = {.Fg1, {1, 0.8, 0.6}},
			.TabSelectedOverline = {.Fg1, {1, 1, 1}},
			.TabDimmed = {.Fg1, {1, 0.6, 0.3}},
			.TabDimmedSelected = {.Fg1, {1, 0.6, 0.5}},
			.TabDimmedSelectedOverline = {.Fg1, {1, 0, 0.7}},
			.SliderGrab = {.Fg1, {1, 0.8, 0.8}},
			.SliderGrabActive = {.Fg1, {1, 0.8, 0.9}},
			.DockingPreview = {.Fg1, {1, 1.1, 1.1}},
			.TableBorderStrong = {.Fg2, {1, 1, 0.8}},
			.TableBorderLight = {.Fg2, {1, 0.8, 0.8}},
			.CheckMark = {.Fg1, {1, 1, 1.1}},
			.ResizeGrip = {.Fg1, {1, 1, 0.9}},
			.ResizeGripHovered = {.Fg1, {1, 1, 0.9}},
			.ResizeGripActive = {.Fg1, {1, 1, 0.9}},
			.SeparatorHovered = {.Fg1, {1, 1, 0.6}},
			.SeparatorActive = {.Fg1, {1, 1, 0.6}},
			.TitleBgActive = {.Fg1, {1, 0.8, 0.2}},
			.NavCursor = {.Fg1, {1, 1, 1.1}},
		}

		for col in imgui.Col {
			if col == .COUNT do break
			info := color_map[col]
			accent := info.base.? or_continue
			base := rgb_to_hsv(t.accents[accent].xyz)
			hsv := base * info.hsv
			colors[col].xyz = hsv_to_rgb(hsv)
		}
	}

	return
}

_save_theme_to_file :: proc(path: string) -> Error {
	t := &ui_theme

	if t.name[0] == 0 {
		return Custom_Error.InvalidName
	}

	saved: _Saved_Theme
	saved.name = string_from_array(t.name[:])
	saved.accents = t.accents
	saved.colors = t.colors
	saved.imgui_colors = t.imgui_colors

	data := json.marshal(saved) or_return
	defer delete(data)

	file := os.create(path) or_return
	defer os.close(file)

	os.write(file, data)

	return nil
}

_load_theme_from_file :: proc(ui: ^UI, path: string, allocator: mem.Allocator) -> (t: _Theme, error: Error) {
	st: _Saved_Theme
	data := os.read_entire_file_from_path(path, context.allocator) or_return
	defer delete(data)

	json.unmarshal(data, &st, allocator=ui.allocators.per_frame) or_return

	t.accents = st.accents
	t.colors = st.colors
	copy(t.name[:len(t.name)-1], st.name)
	t.imgui_colors = st.imgui_colors
	t.path = strings.clone(path, allocator)

	for &color, color_id in t.colors {
		if color == 0 {
			color = _THEME_COLOR_DEFAULTS[color_id]
		}
	}

	return
}

_load_themes :: proc(ui: ^UI) -> Error {
	files := os.read_all_directory_by_path(ui.paths.theme_folder, context.allocator) or_return
	defer os.file_info_slice_delete(files, context.allocator)
	clear(&ui.themes)
	free_all(ui.allocators.themes)

	for file in files {
		t := _load_theme_from_file(ui, file.fullpath, ui.allocators.themes) or_continue
		append(&ui.themes, t)
	}

	return nil
}

_set_theme :: proc(t: _Theme) {
	ui_theme = t
	imgui.GetStyle().Colors = t.imgui_colors
}

_set_theme_by_name :: proc(ui: ^UI, name: string) {
	if name == "" do return
	for &theme in ui.themes {
		if string(cstring(&theme.name[0])) == name {
			_set_theme(theme)
		}
	}
}

_show_settings_editor :: proc(ui: ^UI) -> (changed: bool) {
	cfg := &global_config

	// --------------------------------------------------------------------------
	// Misc
	// --------------------------------------------------------------------------
	changed |= imx.select_enum("Window close policy", &cfg.ui.close_policy)

	if imgui.BeginCombo("Default theme", cfg.ui.default_theme) {
		defer imgui.EndCombo()

		for &theme in ui.themes {
			name_cstr := cstring(&theme.name[0])

			if imgui.MenuItem(name_cstr) {
				set_cstring_buf(cfg.ui.default_theme_buf[:], string(name_cstr))
				changed = true
			}
		}
	}

	changed |= imx.select_enum("Background fit policy", &ui.background.policy)

	if imgui.Button("Change background") {
		async_file_dialog_open(&ui.dialogs.set_background, .Image, {})
	}

	changed |= imgui.Checkbox("Crop cover art to square", &cfg.ui.crop_cover_art)

	// --------------------------------------------------------------------------
	// Notifications
	// --------------------------------------------------------------------------
	imgui.SeparatorText("Notifications")
	changed |= imgui.Checkbox("When a new track starts", &cfg.server.notify_new_track)
	changed |= imgui.Checkbox("When a library scan starts/finishes", &cfg.server.notify_library_scan)
	changed |= imgui.Checkbox("When the playback state changes in the background", &cfg.server.notify_background_playback_state)

	// --------------------------------------------------------------------------
	// Font
	// --------------------------------------------------------------------------
	imgui.SeparatorText("Font")

	changed |= imgui.DragFloat("Font size", &cfg.ui.font_size, 0.08, 8, 36, "%.0f")

	if imgui.BeginCombo("##add_font", "Add font") {
		defer imgui.EndCombo()

		for sf, i in ui.system_fonts {
			imgui.PushIDInt(auto_cast i)
			defer imgui.PopID()

			if imgui.MenuItem(sf.name) {
				config_add_font(cfg, string(sf.name))
				changed = true
			}
		}
	}

	if imgui.BeginListBox("Fonts") {
		defer imgui.EndListBox()

		for font, i in cfg.ui.fonts {
			imgui.PushIDInt(auto_cast i)
			defer imgui.PopID()

			imgui.MenuItem(font.name)
			if imgui.BeginPopupContextItem() {
				defer imgui.EndPopup()

				if imgui.MenuItem("Move up") {
					config_move_font_up(cfg, i)
					changed = true
				}
				if imgui.MenuItem("Move down") {
					config_move_font_down(cfg, i)
					changed = true
				}
				if imgui.MenuItem("Remove") {
					config_remove_font(cfg, i)
					changed = true
					break
				}
			}
		}
	}

	return
}

_set_background :: proc(ui: ^UI, path: string, allocator: mem.Allocator) -> Error {
	if ui.background.texture != nil && !texture_is_outdated(ui.background.texture.?) {
		if ui.background.path == path {
			// Background is already loaded
			return nil
		}
		texture_release(ui.background.texture.?)
	}

	log.debug("Loading background", path, "...")
	TIME_SCOPE("Load background", path)

	if ui.background.path != "" && ui.background.path != path {
		delete(ui.background.path)
		ui.background.path = ""
	}

	ui.background.texture = nil
	h, width, height := texture_create_from_file(path) or_return
	ui.background.size.x = f32(width)
	ui.background.size.y = f32(height)
	ui.background.texture = h

	if ui.background.path != path {
		ui.background.path = strings.clone(path, allocator)
		global_config_dirty = true
	}

	set_cstring_buf(global_config.ui.background_buf[:], path)

	log.debugf("Loaded image with size: %dx%d (%M)", width, height, width*height*4)

	return nil
}

// -----------------------------------------------------------------------------
// Playlists window
// -----------------------------------------------------------------------------

_playlist_row_id_to_playlist_handle :: proc(id: i64) -> Playlist_Handle {
	return transmute(Playlist_Handle) u32(id)
}

_playlist_handle_to_row_id :: proc(h: Playlist_Handle) -> i64 {
	return i64(transmute(u32) h)
}

_playlists_window_show_playlists :: proc(ui: ^UI, w: ^_Playlists_Window) -> bool {
	sv := ui.server
	// --------------------------------------------------------------------------
	// Update rows
	// --------------------------------------------------------------------------
	need_update := false
	
	need_update |= sv.library.playlists_serial != w.playlist_table.serial
	
	if need_update {
		clear(&w.playlist_table.rows)
		w.playlist_table.serial = sv.library.playlists_serial

		it := handle_map.iterator_make(&sv.library.playlists)
		for pl, handle in handle_map.iterate(&it) {
			totals := calculate_track_totals(sv.library, pl.tracks[:])

			append(&w.playlist_table.rows, _make_playlist_row(
				sv.library, pl.uid, pl.name, pl.serial, totals,
				_playlist_handle_to_row_id(pl.handle)
			))
		}

		_playlist_table_sort(&w.playlist_table)
	}

	for &row, row_index in w.playlist_table.rows {
		handle := transmute(Playlist_Handle) u32(row.id)
		pl := library_get_playlist(&sv.library, handle) or_continue
		if row.serial != pl.serial {
			totals := calculate_track_totals(sv.library, pl.tracks[:])
			row = _make_playlist_row(
				sv.library, pl.uid, pl.name, pl.serial, totals, _playlist_handle_to_row_id(pl.handle)
			)
		}
	}

	// --------------------------------------------------------------------------
	// New playlist
	// --------------------------------------------------------------------------
	commit_new_playlist := false

	// Playlist name input
	commit_new_playlist |= imgui.InputTextWithHint(
		"##new_playlist", "New playlist name", cstring(&w.new_playlist_name[0]),
		auto_cast len(w.new_playlist_name),
		{.EnterReturnsTrue}
	)

	// Validate playlist name
	if need_update || imgui.IsItemActive() {
		w.cant_add_playlist_reason = library_can_add_playlist(
			&sv.library, string(cstring(&w.new_playlist_name[0]))
		)
	}
	imgui.SameLine()

	// Add button
	imgui.BeginDisabled(w.cant_add_playlist_reason != .None)
	commit_new_playlist |= imgui.Button("+ New playlist")
	imgui.EndDisabled()

	// Show reason if we can't add the playlist
	switch (w.cant_add_playlist_reason) {
	case .None:
	case .NameExists: imx.set_item_tooltip("Name already used")
	case .NameEmpty: imx.set_item_tooltip("Must enter a name")
	}

	// Add playlist
	if commit_new_playlist && w.cant_add_playlist_reason == .None {
		library_add_playlist(&sv.library, string(cstring(&w.new_playlist_name[0])))
		for &r in w.new_playlist_name do r = 0
	}

	// --------------------------------------------------------------------------
	// Show table
	// --------------------------------------------------------------------------

	imx.title_text("Playlists")
	actions, _ := _playlist_table_show("##playlists", sv, &w.playlist_table, {}, {.Remove})

	if actions.selected_row != nil {
		w.viewing_playlist = _playlist_row_id_to_playlist_handle(w.playlist_table.rows[actions.selected_row.?].id)
	}

	if actions.played_row != nil {
		handle := _playlist_row_id_to_playlist_handle(w.playlist_table.rows[actions.played_row.?].id)
		if pl, found := library_get_playlist(&sv.library, handle); found {
			server_request_play_playlist(sv, pl.tracks[:], pl.uid)
		}
	}

	if actions.remove_row != nil {
		handle := _playlist_row_id_to_playlist_handle(w.playlist_table.rows[actions.remove_row.?].id)
		library_remove_playlist(&sv.library, handle)
	}

	return true
}

_playlists_window_show_tracks :: proc(ui: ^UI, w: ^_Playlists_Window) -> bool {
	sv := ui.server

	playlist := library_get_playlist(&sv.library, w.viewing_playlist.?) or_return

	imx.title_text("Playlist:", playlist.name)
	_track_table_show(
		ui, "##tracks", &w.track_table, playlist.serial, playlist.tracks[:], {}, playlist.uid
	)

	return true
}

_playlists_window_show :: proc(ui: ^UI, w: ^_Playlists_Window) -> (ok: bool) {
	defer if !ok do w.viewing_playlist = nil

	if w.viewing_playlist != nil {
		if imgui.Button("Back") {
			return false
		}

		_playlists_window_show_tracks(ui, w)
	}
	else {
		_playlists_window_show_playlists(ui, w)
	}

	return true
}

_show_playlist_selector_menu :: proc(
	sv: ^Server, label: cstring, exclude: Maybe(Playlist_Handle) = nil
) -> (handle: Playlist_Handle, selected: bool) {
	imgui.BeginMenu(label) or_return
	defer imgui.EndMenu()

	it := handle_map.iterator_make(&sv.library.playlists)
	for it_playlist, h in handle_map.iterate(&it) {
		playlist: ^Playlist = it_playlist
		if exclude != nil && h == exclude.? do continue
		if imgui.MenuItem(playlist.name_cstring) {
			handle = h
			selected = true
		}
	}

	return
}

// -----------------------------------------------------------------------------
// Analysis
// -----------------------------------------------------------------------------

_update_analysis :: proc(ui: ^UI) {
	sv := ui.server
	state := &ui.analysis
	channels := sv.analysis.channels
	state.samplerate = ANALYSIS_SAMPLE_RATE
	state.channels = channels

	if channels == 0 do return

	for ch in 0..<channels {
		if state.raw_output[ch] == nil {
			state.raw_output[ch] = make([]f32, _ANALYSIS_BUFFER_SIZE, ui.allocators.analysis)
		}
	}

	if state.avg_output == nil {
		state.avg_output = make([]f32, _ANALYSIS_BUFFER_SIZE, ui.allocators.analysis)
	}

	if !server_is_paused(sv) {
		server_consume_audio_output(sv, state.raw_output[:channels], global_delta_time)
		dsp.to_mono(state.raw_output[:state.channels], state.avg_output)
	}
}

// -----------------------------------------------------------------------------
// Post-processing
// -----------------------------------------------------------------------------

_post_processing_window_show :: proc(ui: ^UI, w: ^_Post_Processing_Window) -> bool {
	sv := ui.server
	replay_gain_on := w.params.replay_gain_mode == .TrackGain
	p := &w.params

	imgui.SeparatorText("ReplayGain")
	if imgui.Checkbox("Enabled", &replay_gain_on) {
		if replay_gain_on do p.replay_gain_mode = .TrackGain
		else do p.replay_gain_mode = .Ignore
	}

	{
		if imgui.BeginCombo(
			"Pre-amp gain", fmt.caprintf("%ddB", int(p.preamp_gain), allocator=ui.allocators.per_frame)
		) {
			defer imgui.EndCombo()

			imgui.SetItemTooltip("Gain to apply along side ReplayGain. High values may cause clipping.")

			if imgui.MenuItem("+12dB") do p.preamp_gain = 12
			if imgui.MenuItem("+9dB") do p.preamp_gain = 9
			if imgui.MenuItem("+6dB") do p.preamp_gain = 6
			if imgui.MenuItem("+3dB (default, higher may cause clipping)") do p.preamp_gain = 3
			if imgui.MenuItem("+0dB (disable)") do p.preamp_gain = 0
			if imgui.MenuItem("-3dB") do p.preamp_gain = -3
			if imgui.MenuItem("-6dB") do p.preamp_gain = -6
			if imgui.MenuItem("-12dB") do p.preamp_gain = -12
		}
	}

	imgui.SeparatorText("Misc")
	imgui.Checkbox("Hard limit", &p.hard_limiter.enable)

	//imgui.SliderFloat("Pre-amp gain", &w.params.preamp_gain, -10, 10, "%.1fdB")

	if imgui.Button("Apply") {
		playback_thread_set_post_process_params(&sv.playback_thread, w.params)
	}

	return true
}

// -----------------------------------------------------------------------------
// Oscilloscope
// -----------------------------------------------------------------------------

_oscilloscope_window_show :: proc(ui: ^UI, osc: ^_Oscilloscope_Window) -> bool {
	if ui.analysis.channels == 0 do return false
	analysis := &ui.analysis

	// --------------------------------------------------------------------------
	// Settings
	// --------------------------------------------------------------------------
	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Window length")

		current_window_ms := (f32(osc.window_size) / analysis.samplerate) * 1000
		min_window_ms := (_OSCILLOSCOPE_MIN_SAMPLES / analysis.samplerate) * 1000
		max_window_ms := (_OSCILLOSCOPE_MAX_SAMPLES / analysis.samplerate) * 1000
		if imgui.SliderFloat("##window_size", &current_window_ms, min_window_ms, max_window_ms, "%.0fms") {
			osc.window_size = int((current_window_ms / 1000) * analysis.samplerate)
		}

		imgui.SeparatorText("Options")
		imgui.MenuItemBoolPtr("Pinch ends", nil, &osc.pinch_ends)
		if imgui.BeginMenu("Mode") {
			if imgui.MenuItem("Average of channels", nil, osc.display_mode == .Average) {
				osc.display_mode = .Average
			}
			imx.set_item_tooltip("One wave which is the average volume of all channels.")

			if imgui.MenuItem("Layered channels", nil, osc.display_mode == .Layered) {
				osc.display_mode = .Layered
			}
			imx.set_item_tooltip("All channel waves layered on top of each other.")

			if imgui.MenuItem("Stacked channels", nil, osc.display_mode == .Stacked) {
				osc.display_mode = .Stacked
			}
			imx.set_item_tooltip("Separate wave for each channel.")

			imgui.EndMenu()
		}

		imgui.EndPopup()
	}

	osc.window_size = clamp(osc.window_size, _OSCILLOSCOPE_MIN_SAMPLES, _OSCILLOSCOPE_MAX_SAMPLES)

	raw_output := ui.analysis.raw_output[:ui.analysis.channels]
	drawlist := imgui.GetWindowDrawList()

	draw_wave :: proc(
		ui: ^UI,
		drawlist: ^imgui.DrawList,
		samples: []f32,
		pos: [2]f32,
		size: [2]f32,
		pinch: bool,
		color: u32,
	) {
		window_size := len(samples)
		positions := make([][2]f32, len(samples), ui.allocators.per_frame)
		center := pos + {0, size.y*0.5}
		gap := size.x / f32(window_size)
		fade_size := window_size / 8

		for i in 0..<window_size {
			m: f32 = 1
			p := samples[i] * 0.8

			if pinch {
				if i < fade_size {
					m = f32(i) / f32(fade_size)
				}
				else if i > (window_size - fade_size - 1) {
					m = f32(window_size - i - 1) / f32(fade_size)
				}
			}

			positions[i] = center + {gap * f32(i), size.y * 0.5 * p * m}
		}

		imgui.DrawList_AddPolyline(drawlist, raw_data(positions), auto_cast len(positions), color, {}, 2)
	}

	window_size := min(len(raw_output[0]), osc.window_size)
	channels := len(raw_output)
	channel_colors := [AUDIO_MAX_CHANNELS]u32 {
		ui_theme.colors[.LeftChannelWave],
		ui_theme.colors[.RightChannelWave],
	}

	switch osc.display_mode {
	case .Average:
		draw_wave(
			ui, drawlist, analysis.avg_output[:window_size],
			imgui.GetCursorScreenPos(),
			imgui.GetContentRegionAvail(),
			osc.pinch_ends,
			ui_theme.colors[.LeftChannelWave],
		)
	case .Layered:
		for ch, i in raw_output {
			draw_wave(
				ui, drawlist, ch[:window_size],
				imgui.GetCursorScreenPos(),
				imgui.GetContentRegionAvail(),
				osc.pinch_ends,
				channel_colors[i]
			)
		}
	case .Stacked:
		size := imgui.GetContentRegionAvail()
		pos := imgui.GetCursorScreenPos()
		spacing: f32 = 4
		wave_height := size.y / f32(channels)

		for ch in raw_output {
			draw_wave(
				ui, drawlist, ch[:window_size],
				{pos.x, pos.y + spacing}, {size.x, wave_height - spacing},
				osc.pinch_ends,
				ui_theme.colors[.LeftChannelWave],
			)
			pos.y += wave_height
		}
	}

	return true
}

_oscilloscope_window_get_settings :: proc(
	ui: ^UI, osc: ^_Oscilloscope_Window,
	m: ^map[string]string, allocator: mem.Allocator
) -> Error {
	m["Mode"] = reflect.enum_name_from_value(osc.display_mode) or_else "Average"
	m["WindowSize"] = fmt.aprint(osc.window_size, allocator=allocator)
	m["PinchEnds"] = fmt.aprint(osc.pinch_ends, allocator=allocator)

	return nil
}

_oscilloscope_window_load_setting :: proc(ui: ^UI, osc: ^_Oscilloscope_Window, key, value: string) -> Error {

	switch key {
	case "Mode":
		osc.display_mode = reflect.enum_from_name(_Oscilloscope_Display_Mode, value) or_return
		return true
	case "WindowSize":
		osc.window_size = strconv.parse_int(value) or_return
		return true
	case "PinchEnds":
		osc.pinch_ends = strconv.parse_bool(value) or_return
		return true
	}

	return false
}

// -----------------------------------------------------------------------------
// Spectrum
// -----------------------------------------------------------------------------

_spectrum_window_show :: proc(ui: ^UI, state: ^_Spectrum_Window) -> bool {
	analysis := &ui.analysis
	enable_band_hover_info := true
	window_func_changed := false
	if len(analysis.raw_output) == 0 do return false
	if len(analysis.raw_output[0]) == 0 do return false

	// Default band count
	if len(state.bands) == 0 do resize(&state.bands, 80)

	// Settings
	if imgui.BeginPopupContextWindow() {
		defer imgui.EndPopup()
		enable_band_hover_info = false
		band_count := len(state.bands)

		size_options := []int {10, 20, 40, 60, 80, 100, 140, 160}
		imgui.SeparatorText("No. Bands")
		if imx.number_picker_menu_items(size_options, &band_count) {
			resize(&state.bands, band_count)
		}

		imgui.Separator()

		if imgui.BeginMenu("Window") {
			defer imgui.EndMenu()

			items := []imx.Enum_Menu_Item(dsp.Window_Function) {
				{value=.Blackman, name="Blackman (default)"},
				{value=.Nuttall,  name="Nuttall"},
				{value=.Hamming,  name="Hamming"},
				{value=.Hann,     name="Hann"},
				{},
				{value=.Normal,   name="None"},
			}

			window_func_changed |= imx.show_enum_menu_items_ex(items, &state.window_func)
		}

		if imgui.BeginMenu("Mode") {
			defer imgui.EndMenu()
			
			items := []imx.Enum_Menu_Item(_Spectrum_Display_Mode) {
				{value=.Histogram,  name="Histogram"},
				{value=.Heat,       name="Heat map"},
				{value=.Line,       name="Line graph"},
				{value=.LineFilled, name="Line graph (filled)"},
			}

			imx.show_enum_menu_items_ex(items, &state.display_mode)
		}
	}

	// Audio vars
	input_window_size := _SPECTRUM_WINDOW_SIZE
	//mono_input        := analysis.avg_output[:input_window_size]
	mono_input        := analysis.raw_output[0][:input_window_size]
	windowed_input    := make([]f32, input_window_size, ui.allocators.per_frame)

	// Draw vars
	guide_font_scale :: 0.7
	style       := imgui.GetStyle()
	avail_size  := imgui.GetContentRegionAvail()
	graph_pos   := imgui.GetCursorScreenPos()
	graph_size: [2]f32 = {avail_size.x, avail_size.y - imgui.GetTextLineHeight() * guide_font_scale}
	bar_width   := graph_size.x / f32(len(state.bands)) - 1
	bar_spacing := bar_width + 1
	drawlist    := imgui.GetWindowDrawList()
	
	
	// Update window function values
	if len(state.window_values) != len(mono_input) || window_func_changed {
		if state.window_values == nil {
			state.window_values = make([dynamic]f32, ui.allocators.analysis)
		}
		resize(&state.window_values, len(mono_input))
		dsp.make_window(state.window_values[:], state.window_func)
	}
	
	// Apply window function
	for input, i in mono_input {
		windowed_input[i] = input * state.window_values[i]
	}
	
	// Update band frequencies
	if len(state.band_freqs) != len(state.bands) {
		resize(&state.band_freqs, len(state.bands))
		dsp.distribute_band_frequencies(state.band_freqs[:])
	}
	
	// FFT
	for &b in state.bands do b = 0
	dsp.fft_process(&state.fft, windowed_input)
	dsp.fft_extract_bands(state.fft, state.band_freqs[:], analysis.samplerate, state.bands[:])
	
	// Create bands
	Band :: struct {offset, width, peak: f32}
	bands: [dynamic; SPECTRUM_MAX_BANDS]Band

	// Calc band offsets
	{
		x_offset: f32 = 0

		for band in state.bands {
			append(&bands, Band {
				offset = x_offset,
				width = bar_width,
				peak = band,
			})

			x_offset += bar_spacing
		}
	}

	// Update guides
	if state.freq_guide_bands != len(state.band_freqs) || state.freq_guide_width != graph_size.x {
		TIME_SCOPE("Build frequency guides")
		state.freq_guide_bands = len(state.band_freqs)
		state.freq_guide_width = graph_size.x
		min_spacing: f32 = 40
		x_accum: f32 = 10000
		x_offset: f32
		clear(&state.freq_guides)

		for freq in state.band_freqs {
			if len(state.freq_guides) == cap(state.freq_guides) do break

			x_accum += bar_spacing

			if x_accum >= min_spacing {
				guide: _Spectrum_Frequency_Guide
				guide.offset = x_offset
				x_accum = 0
				if freq > 10_000 {
					fmt.bprintf(guide.str[:], "%dKHz", int(freq/1000))
				}
				else if freq > 1000 {
					fmt.bprintf(guide.str[:], "%.1fKHz", freq/1000)
				}
				else {
					fmt.bprintf(guide.str[:], "%dHz", int(freq))
				}

				append(&state.freq_guides, guide)
			}

			x_offset += bar_spacing
		}
	}

	// Draw bands
	draw_band_bars :: proc(
		drawlist: ^imgui.DrawList, pos, size: [2]f32, bands: []Band
	) {
		quiet_color := imgui.ColorConvertU32ToFloat4(ui_theme.colors[.VolumeLow])
		loud_color := imgui.ColorConvertU32ToFloat4(ui_theme.colors[.VolumeHigh])

		for band in bands {
			peak := clamp(band.peak, 0, 1)
			color := linalg.lerp(quiet_color, loud_color, clamp(peak, 0, 1))
			p_min: [2]f32 = {pos.x + band.offset, pos.y + size.y * (1 - peak)}
			p_max: [2]f32 = {pos.x + band.offset + band.width, pos.y + size.y}

			imgui.DrawList_AddRectFilled(drawlist, p_min, p_max, imgui.GetColorU32ImVec4(color))
		}
	}

	draw_band_heat :: proc(
		drawlist: ^imgui.DrawList, pos, size: [2]f32, bands: []Band
	) {
		quiet_color := imgui.ColorConvertU32ToFloat4(ui_theme.colors[.VolumeLow])
		loud_color := imgui.ColorConvertU32ToFloat4(ui_theme.colors[.VolumeHigh])

		quiet_color.a = 0
		loud_color.a = 1

		for band in bands {
			peak := clamp(band.peak, 0, 1)
			color := linalg.lerp(quiet_color, loud_color, clamp(peak, 0, 1))
			p_min: [2]f32 = {pos.x + band.offset, pos.y}
			p_max: [2]f32 = {pos.x + band.offset + band.width, pos.y + size.y}

			imgui.DrawList_AddRectFilled(drawlist, p_min, p_max, imgui.GetColorU32ImVec4(color))
		}
	}
	
	draw_line_graph :: proc(
		drawlist: ^imgui.DrawList, pos, size: [2]f32, bands: []Band, allocator: mem.Allocator, fill: bool
	) {
		positions := make([][2]f32, len(bands), allocator)
		gap := (size.x/f32(len(bands)))
		x := pos.x
		color := imgui.GetColorU32(.PlotLines)

		if fill do imgui.DrawList_PathLineTo(drawlist, pos + {0, size.y})

		for band, i in bands {
			p := pos + {x, size.y * (1 - band.peak)}
			positions[i] = p
			if fill do imgui.DrawList_PathLineTo(drawlist, p)
			x += gap
		}

		if fill do imgui.DrawList_PathLineTo(drawlist, pos + size)

		if fill do imgui.DrawList_PathFillConcave(drawlist, ui_theme.colors[.VolumeHigh])

		imgui.DrawList_AddPolyline(drawlist, raw_data(positions), auto_cast len(positions), color, {}, 2)
	}

	draw_frequency_guides :: proc(
		drawlist: ^imgui.DrawList,
		guides: []_Spectrum_Frequency_Guide,
		pos: [2]f32,
	) {
		imx.push_font_scale(guide_font_scale)
		defer imgui.PopFont()
		color := imgui.GetColorU32(.TextDisabled)

		for &guide in guides {
			str := string_from_array(guide.str[:])
			imgui.DrawList_AddText(drawlist, pos + {guide.offset, 0}, color, imx.string_to_ptrs(str))
		}
	}

	switch state.display_mode {
	case .Histogram:
		//draw_band_bars(drawlist, graph_pos, graph_size, bands[:])
		//draw_band_bars(drawlist, graph_pos, graph_size, bands[:])
		imx.draw_bars(
			drawlist, graph_pos + {0, graph_size.y}, graph_pos + {graph_size.x, 0}, state.bands[:],
			ui_theme.colors[.VolumeLow], ui_theme.colors[.VolumeHigh]
		)
	case .Heat:
		draw_band_heat(drawlist, graph_pos, graph_size, bands[:])
	case .Line:
		draw_line_graph(drawlist, graph_pos, graph_size, bands[:], ui.allocators.per_frame, false)
	case .LineFilled:
		draw_line_graph(drawlist, graph_pos, graph_size, bands[:], ui.allocators.per_frame, true)
	}
	draw_frequency_guides(drawlist, state.freq_guides[:], graph_pos + {0, graph_size.y + style.FramePadding.y})

	// Band info on hover
	if enable_band_hover_info do for band, band_index in bands {
		p_min := graph_pos + {band.offset, 0}
		p_max := p_min + {band.width, graph_size.y}

		if imgui.IsMouseHoveringRect(p_min, p_max) && imgui.BeginTooltip() {
			if band_index + 1 < len(state.band_freqs) {
				imx.textf(64, "Frequency: %.1f-%.1fHz", 
					state.band_freqs[band_index], state.band_freqs[band_index+1]
				)
			}
			else {
				imx.textf(64, "Frequency: %.1f+Hz", state.band_freqs[band_index])
			}
			imx.textf(64, "Gain: %.1fDb", dsp.amp_to_gain(state.bands[band_index]))

			imgui.DrawList_AddRect(drawlist, p_min, p_max, imgui.GetColorU32(.TextDisabled))
			imgui.EndTooltip()
		}
	}

	return true
}

_spectrum_window_get_settings :: proc(
	ui: ^UI, state: ^_Spectrum_Window, output: ^map[string]string,
	allocator: mem.Allocator
) -> Error {
	output["Bands"] = fmt.aprint(len(state.bands), allocator=allocator)
	output["Window"] = fmt.aprint(state.window_func, allocator=allocator)
	output["Mode"] = fmt.aprint(state.display_mode, allocator=allocator)
	return nil
}

_spectrum_window_load_setting :: proc(
	ui: ^UI, state: ^_Spectrum_Window,
	key, value: string
) -> Error {

	switch key {
	case "Bands":
		v := strconv.parse_int(value) or_break
		v = clamp(v, 10, SPECTRUM_MAX_BANDS)
		resize(&state.bands, v)
	case "Window":
		state.window_func = reflect.enum_from_name(dsp.Window_Function, value) or_break
	case "Mode":
		state.display_mode = reflect.enum_from_name(_Spectrum_Display_Mode, value) or_break
	}

	return nil
}

// -----------------------------------------------------------------------------
// Wavebar
// -----------------------------------------------------------------------------
_wavebar_window_show :: proc(ui: ^UI, state: ^_Wavebar_Window) -> bool {
	sv := ui.server
	track_id := sv.current_track_id

	_build_data_points :: proc(state: ^_Wavebar_Builder) -> bool {
		dec: Decoder

		decoder_open(&dec, state.track_url, nil) or_return
		defer decoder_close(&dec)

		buffer_size := dec.frame_count / _WAVEBAR_NUM_DATA_POINTS

		buf := make([]f32, buffer_size)
		defer delete(buf)

		for i in 0..<_WAVEBAR_NUM_DATA_POINTS {
			status := decoder_fill_buffer(&dec, {buf}, dec.samplerate)

			if sync.atomic_load(&state.want_cancel) do break

			peak: f32

			for v in buf {
				peak = max(abs(v), peak)
			}

			state.data_points[i] = peak
			sync.atomic_add(&state.data_points_calculated, 1)

			if status != .Complete do break
		}

		return true
	}

	_thread_proc :: proc(thr: ^thread.Thread) {
		state := cast(^_Wavebar_Builder) thr.data
		_build_data_points(state)
	}

	// --------------------------------------------------------------------------
	// Settings
	// --------------------------------------------------------------------------

	if imgui.BeginPopupContextWindow() {
		defer imgui.EndPopup()

		items := []imx.Enum_Menu_Item(imx.Bar_Color_Mode) {
			{value=.Gradient, name="Gradient"},
			{value=.Flat, name="Flat"},
		}

		imgui.SeparatorText("Color Mode")
		imx.show_enum_menu_items_ex(items, &state.color_mode)
	}

	// --------------------------------------------------------------------------
	// Update
	// --------------------------------------------------------------------------
	if track_id != state.displayed_track {
		state.displayed_track = track_id

		// Cancel thread if it's running
		if state.decoder_thread != nil {
			sync.atomic_store(&state.bg.want_cancel, true)
			thread.join(state.decoder_thread)
			state.decoder_thread = nil
			state.bg.want_cancel = false
		}

		if track_id == 0 do return false

		for &f in state.bg.data_points[:state.bg.data_points_calculated] do f = 0
		state.bg.data_points_calculated = 0
		track := sv.library.tracks[track_id] or_return
		state.bg.track_url = track.url

		state.decoder_thread = thread.create(_thread_proc, .Low)
		state.decoder_thread.data = &state.bg
		state.decoder_thread.init_context = context
		thread.start(state.decoder_thread)
	}

	// --------------------------------------------------------------------------
	// Input
	// --------------------------------------------------------------------------
	if imgui.IsWindowHovered() && imgui.IsMouseClicked(.Left) {
		p_min := imgui.GetCursorScreenPos()
		p_max := p_min + imgui.GetContentRegionAvail()

		pos := linalg.unlerp(p_min.x, p_max.x, imgui.GetMousePos().x)
		pos = clamp(pos, 0, 1)
		server_seek(sv, int(pos * f32(sv.track_info.duration)))
	}

	// --------------------------------------------------------------------------
	// Display
	// --------------------------------------------------------------------------
	data_points := state.bg.data_points[:]

	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	defer imgui.PopStyleVar()

	track_pos := server_get_track_position_seconds(sv)
	track_duration := sv.track_info.duration
	if track_duration <= 0 do return false
	track_progress := f32(f64(track_pos) / f64(track_duration))

	// Draw histogram
	{
		drawlist := imgui.GetWindowDrawList()
		pos := imgui.GetCursorScreenPos()
		size := imgui.GetContentRegionAvail()

		left_data_points := int(track_progress * _WAVEBAR_NUM_DATA_POINTS)
		right_data_points := _WAVEBAR_NUM_DATA_POINTS - left_data_points
		bar_size := size.x / f32(_WAVEBAR_NUM_DATA_POINTS)
		left_size := f32(left_data_points) * bar_size
		right_size := f32(right_data_points) * bar_size

		draw_wave :: proc(drawlist: ^imgui.DrawList, pos, size: [2]f32, points: []f32, brightness: f32, color_mode: imx.Bar_Color_Mode) {
			height := size.y * 0.5
			inner_color_v := imgui.ColorConvertU32ToFloat4(ui_theme.colors[.WaveBarInner])
			outer_color_v := imgui.ColorConvertU32ToFloat4(ui_theme.colors[.WaveBarOuter])

			inner_color_v.rgb *= brightness
			outer_color_v.rgb *= brightness
			inner_color := imgui.GetColorU32ImVec4(inner_color_v)
			outer_color := imgui.GetColorU32ImVec4(outer_color_v)

			imx.draw_bars(
				imgui.GetWindowDrawList(), 
				{pos.x, pos.y + height}, {pos.x + size.x, pos.y}, points, inner_color, outer_color,
				spacing = 0, min_height = 1, color_mode = color_mode,
			)
			imx.draw_bars(
				imgui.GetWindowDrawList(), 
				{pos.x, pos.y + height}, {pos.x + size.x, pos.y + size.y}, points, inner_color, outer_color,
				spacing = 0, min_height = 1, color_mode = color_mode,
			)
		}

		draw_wave(
			drawlist, pos,
			{left_size, size.y}, data_points[:left_data_points],
			1, state.color_mode
		)
		draw_wave(
			drawlist,
			{pos.x + left_size, pos.y}, {right_size, size.y},
			data_points[left_data_points:],
			0.4, state.color_mode
		)
	}


	return true
}

_wavebar_window_get_settings :: proc(
	ui: ^UI, w: ^_Wavebar_Window, out: ^map[string]string, allocator: mem.Allocator
) -> Error {
	out["ColorMode"] = reflect.enum_name_from_value(w.color_mode) or_else ""

	return nil
}

_wavebar_window_load_setting :: proc(w: ^_Wavebar_Window, key, value: string) -> Error {
	switch key {
	case "ColorMode": w.color_mode = reflect.enum_from_name(imx.Bar_Color_Mode, value) or_break
	}

	return nil
}

// -----------------------------------------------------------------------------
// Folder tree
// -----------------------------------------------------------------------------

_folder_tree_window_select_folder :: proc(
	library: Library, w: ^_Folder_Tree_Window, folder: ^_Folder_Tree_Node
) {
	clear(&w.tracks)
	library_get_tracks_in_folder(library, folder.origin, &w.tracks)
	w.selected_folder = folder
	w.track_table.serial = 0
}

_folder_tree_window_show_folders :: proc(
	ui: ^UI, w: ^_Folder_Tree_Window
) -> bool {
	sv := ui.server
	library := &sv.library


	COLUMN_NAME      :: 0
	COLUMN_LENGTH    :: 1
	COLUMN_FILE_SIZE :: 2
	COLUMN__COUNT    :: 3

	// --------------------------------------------------------------------------
	// Build if needed
	// --------------------------------------------------------------------------
	if w.tree_serial != library.folder_tree_serial {
		w.tree_serial = library.folder_tree_serial
		free_all(ui.allocators.folder_tree)
		w.root_node = {}

		make_node :: proc(node: ^_Folder_Tree_Node, l: ^Library_Folder, allocator: mem.Allocator) {
			node.totals   = l.totals
			node.name     = l.name_cstring
			node.origin   = l
			node.children = make([]_Folder_Tree_Node, l.child_count, allocator)
			
			i := 0
			for head := l.first_child; head != nil; head = head.next {
				make_node(&node.children[i], head, allocator)
				i += 1
			}
		}

		make_node(&w.root_node, &library.folder_tree, ui.allocators.folder_tree)
	}

	// --------------------------------------------------------------------------
	// Show table
	// --------------------------------------------------------------------------

	_Actions :: struct {
		select:        ^_Folder_Tree_Node,
		play:          ^_Folder_Tree_Node,
		add_to_queue:  ^_Folder_Tree_Node,
	}
	actions: _Actions

	table_flags := imgui.TableFlags_BordersInner|
		imgui.TableFlags_RowBg|
		imgui.TableFlags_ScrollY
	
	imgui.BeginTable("##folders", COLUMN__COUNT, table_flags) or_return
	defer imgui.EndTable()

	on_show_node :: proc(sv: ^Server, actions: ^_Actions, node: ^_Folder_Tree_Node) {
		if imgui.IsItemClicked(.Middle) {
			actions.play = node
		}

		if imgui.BeginPopupContextItem() {
			defer imgui.EndPopup()

			if imgui.MenuItem("Play") {
				actions.play = node
			}

			if imgui.MenuItem("Add to queue") {
				actions.add_to_queue = node
			}
		}
	}

	show_node :: proc(
		sv:      ^Server,
		actions: ^_Actions,
		w:       ^_Folder_Tree_Window,
		node:    ^_Folder_Tree_Node
	) {
		library := &sv.library

		imgui.TableNextRow()

		imgui.PushIDPtr(node)
		defer imgui.PopID()


		if imgui.TableSetColumnIndex(COLUMN_LENGTH) {
			imx.text(64, node.totals.track_count)
		}

		if imgui.TableSetColumnIndex(COLUMN_FILE_SIZE) {
			imx.textf(64, "%M", node.totals.file_size)
		}
		
		if imgui.TableSetColumnIndex(COLUMN_NAME) {
			// Small button to show all tracks contained in folder and subfolders
			if node.children != nil {
				if imgui.SmallButton(ICON_MAGNIFY) {
					actions.select = node
				}
				imgui.SetItemTooltip("View tracks")
				imgui.SameLine()
			}
			
			// Playing highlight
			if node.origin.uid != 0 && node.origin.uid == sv.playback.playlist_uid {
				imgui.TableSetBgColor(.RowBg0, ui_theme.colors[.PlayingHighlight])
			}

			// Selectable part
			if node.children != nil {
				if imgui.TreeNodeEx(node.name, {.SpanAllColumns}) {
					defer imgui.TreePop()

					on_show_node(sv, actions, node)
					
					for &child in node.children {
						show_node(sv, actions, w, &child)
					}
				}
				else {
					on_show_node(sv, actions, node)
				}
			}
			else {
				if imgui.Selectable(node.name) {
					actions.select = node
				}

				on_show_node(sv, actions, node)
			}
		}
	}

	get_first_node_with_multiple_children :: proc(n: ^_Folder_Tree_Node) -> ^_Folder_Tree_Node {
		if len(n.children) > 1 do return n
		else if len(n.children) == 0 do return nil
		return get_first_node_with_multiple_children(&n.children[0])
	}

	root := get_first_node_with_multiple_children(&w.root_node)
	if root == nil do root = &w.root_node
	show_node(sv, &actions, w, root)
	
	if actions.select != nil {
		_folder_tree_window_select_folder(library^, w, actions.select)
	}

	if actions.play != nil {
		_folder_tree_window_select_folder(library^, w, actions.play)
		server_request_play_playlist(sv, w.tracks[:], w.selected_folder.origin.uid)
	}

	if actions.add_to_queue != nil {
		tracks: [dynamic]Track_ID
		defer delete(tracks)
		library_get_tracks_in_folder(library^, actions.add_to_queue.origin, &tracks)
		playback_queue_add(&sv.playback, tracks[:], actions.add_to_queue.origin.uid)
	}

	return true
}

_folder_tree_window_show_tracks :: proc(
	ui: ^UI, w: ^_Folder_Tree_Window
) {
	if imgui.Button("Back") {
		w.selected_folder = nil
		return
	}

	_track_table_show(
		ui, "##tracks", &w.track_table, ui.server.library.serial,
		w.tracks[:], {.NoRemove}, w.selected_folder.origin.uid
	)
}

_folder_tree_window_show_focused :: proc(ui: ^UI, w: ^_Folder_Tree_Window) {
	if w.tree_serial != ui.server.library.folder_tree_serial {
		w.selected_folder = nil
	}

	if w.selected_folder != nil {
		_folder_tree_window_show_tracks(ui, w)
	}
	else {
		_folder_tree_window_show_folders(ui, w)
	}
}

// -----------------------------------------------------------------------------
// Misc
// -----------------------------------------------------------------------------

_table_select_row :: proc(table: ^$T, row_index: int, keep_selection: bool) {
	row := &table.rows[row_index]
	rows := table.rows[:]

	ctrl := imgui.IsKeyDown(.ImGuiMod_Ctrl)
	shift := imgui.IsKeyDown(.ImGuiMod_Shift)

	if !ctrl && !shift {
		if !keep_selection || !row.selected {
			for &r in rows do r.selected = false
		}
		row.selected = true
	}
	else if (ctrl && shift) || shift {
		lo := max(int)
		hi := -1
		for r, i in rows {
			if r.selected {
				if i < row_index do lo = min(lo, i)
				if i > row_index do hi = max(hi, i)
			}
		}

		if lo == max(int) && hi == -1 {
			for &r in rows[0:row_index+1] do r.selected = true
		} else if hi == -1 {
			for &r in rows[lo:row_index+1] do r.selected = true
		} else if lo == max(int) {
			for &r in rows[row_index+1:hi] do r.selected = true
		} else if (hi-row_index) < (row_index-lo) {
			for &r in rows[row_index:hi+1] do r.selected = true
		} else {
			for &r in rows[lo:row_index+1] do r.selected = true
		}
	}
	else if ctrl {
		row.selected = true
	}
}

_refresh_fonts :: proc(ui: ^UI) -> Error {
	for font in ui.system_fonts do font_free(font)
	free_all(ui.allocators.fonts)
	ui.system_fonts = font_list_system_fonts(ui.allocators.fonts) or_return

	return nil
}

// Ensure that there is enough space for a resizable table to 
// prevent the bug where all columns have NaN width and ImGui explodes.
// Not sure if this actually works or not :/.
_check_table_size :: proc() -> bool {
	s := imgui.GetContentRegionAvail()
	return s.x >= 50 && s.y >= 20
}

_is_key_chord_pressed_in_window :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsWindowFocused({.ChildWindows}) && imgui.IsKeyChordPressed(auto_cast (mods | key))
}

_is_key_chord_pressed :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsKeyChordPressed(auto_cast (mods | key))
}

_go_to_album :: proc(ui: ^UI, id: Album_ID) {
	_track_group_window_select_group(ui, &ui.windows.albums, .Album, id)
	ui.window_state[.Albums].bring_to_front = true
}

_go_to_artist :: proc(ui: ^UI, id: Artist_ID) {
	_track_group_window_select_group(ui, &ui.windows.artists, .Artist, id)
	ui.window_state[.Artists].bring_to_front = true
}

_go_to_genre :: proc(ui: ^UI, id: Genre_ID) {
	_track_group_window_select_group(ui, &ui.windows.genres, .Genre, id)
	ui.window_state[.Genres].bring_to_front = true
}

// -----------------------------------------------------------------------------
// Layout
// -----------------------------------------------------------------------------

_imgui_settings_open_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, name: cstring
) -> rawptr {
	for info, id in _WINDOW_INFO {
		if string(info.internal_name) == string(name) {
			return cast(rawptr) (uintptr(id) + 1)
		}
	}

	return nil
}

_imgui_settings_read_line_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line: cstring
) {
	context = runtime.default_context()
	ui := cast(^UI) handler.UserData
	id := cast(_Window_ID) (uintptr(entry) - 1)
	if !reflect.enum_value_has_name(id) do return

	tokens := strings.split_n(string(line), "=", 2, ui.allocators.per_frame)
	if len(tokens) < 2 do return

	state := &ui.window_state[id]
	info := _WINDOW_INFO[id]

	if .DontSave in info.flags do return
	
	if tokens[0] != "_Open" {
		if info.settings_load_proc != nil {
			info.settings_load_proc(ui, tokens[0], tokens[1])
		}
	}
	else {
		state.open = strconv.parse_bool(tokens[1]) or_else state.open
	}
}

_imgui_settings_write_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
) {
	context = runtime.default_context()
	ui := cast(^UI) handler.UserData
	allocator := ui.allocators.per_frame

	for state, id in ui.window_state {
		info := _WINDOW_INFO[id]
		m: map[string]string

		if .DontSave in info.flags do continue
		
		imgui.TextBuffer_append(out_buf,
			imx.string_to_ptrs(fmt.aprintln(
				"["+PROGRAM_ID+"][", info.internal_name, "]", sep="", allocator=allocator
			))
		)
		imgui.TextBuffer_append(out_buf, 
			imx.string_to_ptrs(fmt.aprintln("_Open=", state.open, sep="", allocator=allocator))
		)

		if info.settings_save_proc == nil do continue
		
		info.settings_save_proc(ui, &m, allocator)

		for k, v in m {
			str := fmt.aprintln(k, "=", v, sep="", allocator=allocator)
			imgui.TextBuffer_append(out_buf, imx.string_to_ptrs(str))
		}
	}
}

// -----------------------------------------------------------------------------
// Debug
// -----------------------------------------------------------------------------

_show_memory_tracking :: proc(ui: ^UI) -> bool {
	sv := ui.server

	if !global_command_opts.memory_debug {
		imx.text_unformatted("Memory debugging is disabled. Launch program with -memory-debug argument.")
		return false
	}

	show_info :: proc(t: mem.Tracking_Allocator, flags: Allocator_Map_Entry_Flags) -> bool {
		imx.begin_kv_table("##kv", {}) or_return
		defer imx.end_kv_table()

		if .IsTemp not_in flags {
			imx.kv_row("Allocation count", t.total_allocation_count)
			imx.kv_row("Free count", t.total_free_count)
			imx.kv_rowf("Current allocated", "%M", t.current_memory_allocated)
			imx.kv_rowf("Total allocated", "%M", t.total_memory_allocated)
		}
		imx.kv_rowf("Peak usage", "%M", t.peak_memory_allocated)
		return true
	}

	show_map :: proc(m: Allocator_Map) {
		total_usage: i64
		for name, entry in m {
			imx.title_text(name)
			show_info(entry.tracker^, entry.flags)
			total_usage += entry.tracker.current_memory_allocated
		}

		imx.push_font_scale(1.2)
		imx.textf(64, "Total usage: %M", total_usage)
		imgui.PopFont()
	}

	imgui.BeginTabBar("##memory_tabs") or_return
	defer imgui.EndTabBar()

	if imgui.BeginTabItem("Misc") {
		t := get_global_tracking_allocator()
		show_info(t, {})
		for _, e in t.allocation_map {
			imx.textf(256, "%t: %M", e.location, e.size)
		}
		imgui.EndTabItem()
	}

	if imgui.BeginTabItem("UI") {
		show_map(ui.allocator_map)
		imgui.EndTabItem()
	}

	if imgui.BeginTabItem("Server") {
		show_map(sv.allocator_map)
		imgui.EndTabItem()
	}

	if imgui.BeginTabItem("Library") {
		show_map(sv.library.allocator_map)
		imgui.EndTabItem()
	}

	return true
}
