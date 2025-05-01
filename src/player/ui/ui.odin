/*
	RAT MP: A lightweight graphical music player
    Copyright (C) 2025 Jamie Dennis

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
package ui

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:strings"
import "core:thread"
import "core:slice"
import "core:math"
import "core:os"
import "core:os/os2"
import "core:fmt"
import "core:strconv"
import "core:time"
import "core:path/filepath"

import imgui "libs:odin-imgui"

import "player:config"
import "player:library"
import "player:util"
import "player:playback"
import "player:video"
import "player:theme"
import "player:drag_drop"
import "player:analysis"
import "player:build"
import "player:system_paths"

ICON_FONT := #load("FontAwesome.otf")

STOP_ICON :: ""
SHUFFLE_ICON :: ""
PREV_TRACK_ICON :: ""
NEXT_TRACK_ICON :: ""
PLAY_ICON :: ""
PAUSE_ICON :: ""

@private
_Layout_Name :: [64]u8

@private
Track_ID :: library.Track_ID
@private
Playlist_ID :: library.Playlist_ID
@private
Library :: library.Library
@private
Playback :: playback.State

Window :: enum {
	Library,
	Navigation,
	Artists,
	Albums,
	Folders,
	Genres,
	Queue,
	PlaylistTabs,
	Playlist,
	Metadata,
	ThemeEditor,
	ReplaceMetadata,
	EditMetadata,
	PeakMeter,
	Spectrum,
	WavePreview,
}

Window_Category :: enum {
	Music,
	Info,
	Editing,
	Visualizers,
}

WINDOW_FIRST_VISUALIZER :: Window.PeakMeter

Window_Info :: struct {
	name: cstring,
	internal_name: cstring,
	category: Window_Category,
}

window_info := [Window]Window_Info {
	.Library = {
		name = "Library", internal_name = "library",
		category = .Music,
	},
	.Navigation = {
		name = "Navigation", internal_name = "navigation",
		category = .Music,
	},
	.Artists = {
		name = "Artists", internal_name = "artists",
		category = .Music,
	},
	.Albums = {
		name = "Albums", internal_name = "albums",
		category = .Music,
	},
	.Folders = {
		name = "Folders", internal_name = "folders",
		category = .Music,
	},
	.Genres = {
		name = "Genres", internal_name = "genres",
		category = .Music,
	},
	.Queue = {
		name = "Queue", internal_name = "queue",
		category = .Info,
	},
	.Playlist = {
		name = "Playlist", internal_name = "playlist",
		category = .Music,
	},
	.PlaylistTabs = {
		name = "Playlists (Tabs)", internal_name = "playlist_tabs",
		category = .Music,
	},
	.Metadata = {
		name = "Metadata", internal_name = "metadata",
		category = .Info,
	},
	.ThemeEditor = {
		name = "Edit Theme", internal_name = "theme_editor",
		category = .Editing,
	},
	.ReplaceMetadata = {
		name = "Replace Metadata", internal_name = "replace_metadata",
		category = .Editing,
	},
	.EditMetadata = {
		name = "Edit Metadata", internal_name = "edit_metadata",
		category = .Editing,
	},
	.PeakMeter = {
		name = "Peak Meter", internal_name = "peak_meter",
		category = .Visualizers,
	},
	.Spectrum = {
		name = "Spectrum", internal_name = "spectrum",
		category = .Visualizers,
	},
	.WavePreview = {
		name = "Wave Preview", internal_name = "wave_preview",
		category = .Visualizers,
	},
}

window_category_info := [Window_Category]struct {
	name: cstring,	
} {
	.Editing = {"Editing"},
	.Info = {"Info"},
	.Music = {"Music"},
	.Visualizers = {"Visualizers"},
}

DEFAULT_LAYOUT_INI := #load("default_layout.ini")

@private
Playlist_Group_Window :: struct {
	selected_playlist_id: Maybe(Playlist_ID),
	sort_spec: library.Playlist_Sort_Spec,
}

@private
_Playlist_Window :: struct {
	playlist_id: library.Playlist_ID,

	filter: [256]u8,
	filtered_tracks: []library.Track_ID,
	length_of_playlist_when_filtered: int,

	sort_spec: library.Track_Sort_Spec,
	length_of_playlist_when_sorted: int,
}

@private
Offset_Length :: struct {
	offset, length: int,
}

@private
_Metadata_Window :: struct {
	track: Track_ID,
	thumbnail: video.Texture,
	comment: cstring,
}

@private
_Window_State :: struct {
	flags: imgui.WindowFlags,
	show: bool,
	bring_to_front: bool,
}

@private
_Background_Metadata_Scan :: struct {
	exclude_path_hashes: []u32,
	paths: [dynamic][512]u8,
	input_file_count: int,
	output: library.Track_Data,
}

State :: struct {
	ctx: runtime.Context,

	deferred_files: struct {
		pool: [dynamic]u8,
		files: [dynamic]Offset_Length,
		files_loaded: int,
		scanning: bool,
	},

	metadata: _Metadata_Window,

	selection: [dynamic]library.Track_ID,
	selection_playlist_id: library.Playlist_ID,
	selected_playlist: library.Playlist_ID,

	show_help: bool,
	show_preferences: bool,
	show_about: bool,

	new_playlist_popup_id: imgui.ID,

	background: video.Texture,
	background_width: int,
	background_height: int,

	artists_window: Playlist_Group_Window,
	albums_window: Playlist_Group_Window,
	folders_window: Playlist_Group_Window,
	genres_window: Playlist_Group_Window,

	enable_imgui_theme_editor: bool,
	enable_imgui_demo_window: bool,

	platform_drag_drop_payload: [dynamic]string,
	want_to_drop_platform_drag_drop_payload: bool,

	layout_that_we_want_to_load: []u8,
	free_layout_after_load: bool,

	layout_names: [dynamic]_Layout_Name,
	//metadata_save_job: ^lib.Metadata_Save_Job,

	library_window: _Playlist_Window,
	playlist_windows: map[library.Playlist_ID]_Playlist_Window,

	windows: [Window]_Window_State,

	background_metadata_scan: _Background_Metadata_Scan,
	background_metadata_scan_thread: ^thread.Thread,
}

init :: proc() -> (ui: State, ok: bool) {
	ui.ctx = context
	io := imgui.GetIO()
	io.ConfigFlags |= {.DockingEnable, .NavEnableKeyboard}
	
	// Load settings if needed
	if !os.exists(cast(string) io.IniFilename) {
		log.debug("Loading default layout")
		imgui.LoadIniSettingsFromMemory(cstring(&DEFAULT_LAYOUT_INI[0]), len(DEFAULT_LAYOUT_INI))
	}

	log.debug("ImGui version: ", imgui.VERSION)

	//signal.install_handler(signal_handler)

	// Set window flags
	ui.windows[.Metadata].flags |= {.AlwaysVerticalScrollbar}

	// Set up system drag-drop
	// @FixMe
	/*drag_drop.set_interface(
		&{
			begin = _ext_drag_drop_begin,
			add_file = _ext_drag_drop_add_file,
			cancel = _ext_drag_drop_cancel,
			drop = _ext_drag_drop_drop,
			mouse_over = _ext_drag_drop_mouse_over,
		}
	)*/

	_scan_layouts(&ui)

	ok = true
	return
}

// Holds on to pointer !!!
install_imgui_settings_handler :: proc(ui: ^State) {
	io := imgui.GetIO()

	// Add settings handler
	handler := imgui.SettingsHandler {
		TypeName = build.PROGRAM_NAME,
		TypeHash = imgui.cImHashStr(build.PROGRAM_NAME),
		ReadOpenFn = _imgui_settings_handler_open_proc,
		ReadLineFn = _imgui_settings_handler_read_line_proc,
		WriteAllFn = _imgui_settings_handler_write_proc,
		UserData = ui,
	}

	imgui.AddSettingsHandler(&handler)
	//imgui.SaveIniSettingsToDisk(io.IniFilename);
	imgui.LoadIniSettingsFromDisk(io.IniFilename)
}

destroy :: proc(ui: State) {
	if ui.deferred_files.pool != nil {
		delete(ui.deferred_files.pool)
	}

	video.impl.destroy_texture(ui.background)
	video.impl.destroy_texture(ui.metadata.thumbnail)
	if ui.metadata.comment != nil {delete(ui.metadata.comment)}
}

@private
_load_fonts :: proc(prefs: ^config.Preferences) {
	@static loaded_font: [512]u8
	@static loaded_font_size: int
	@static loaded_icon_size: int

	io := imgui.GetIO()

	font_path := cstring(raw_data(prefs.strings[.Font][:]))
	log.debug("Font path:", font_path)
	when ODIN_OS == .Windows {
		if font_path == "" || !os.exists(string(font_path)) {
			font_path = "C:\\Windows\\Fonts\\calibrib.ttf"
		}
	}
	font_size := prefs.numbers[.FontSize]
	icon_size := prefs.numbers[.IconSize]

	if cstring(&loaded_font[0]) == font_path && loaded_font_size == font_size && loaded_icon_size == icon_size {
		return
	}

	video.impl.invalidate_imgui_objects()
	defer video.impl.create_imgui_objects()

	fonts := io.Fonts
	cfg := imgui.FontConfig {
		FontDataOwnedByAtlas = false,
		OversampleH = 2,
		OversampleV = 2,
		GlyphMaxAdvanceX = max(f32),
		RasterizerMultiply = 1,
		RasterizerDensity = 1,
		EllipsisChar = max(imgui.Wchar),
		MergeMode = true,
	}

	imgui.FontAtlas_Clear(fonts)

	if font_path != "" && os.exists(string(font_path)) {
		if imgui.FontAtlas_AddFontFromFileTTF(fonts, font_path, auto_cast font_size) == nil {
			imgui.FontAtlas_AddFontDefault(fonts)
		}
	}
	else {
		imgui.FontAtlas_AddFontDefault(fonts)
	}

	icon_ranges := []imgui.Wchar {
		0xf048, 0xf052, // Playback controls
		0xf026, 0xf028, // Volume
		0xf074, 0xf074, // Shuffle
		0
	}

	imgui.FontAtlas_AddFontFromMemoryTTF(fonts, raw_data(ICON_FONT), 
		cast(i32) len(ICON_FONT), auto_cast icon_size, &cfg, raw_data(icon_ranges))

	util.copy_cstring(loaded_font[:], font_path)
	loaded_font_size = font_size
	loaded_icon_size = icon_size
}

apply_prefs :: proc(ui: ^State, prefs: ^config.Preferences) {
	log.debug("Applying preferences...")
	io := imgui.GetIO()
	
	// Load background
	{
		@static loaded_background: [512]u8
		path := config.get_string(prefs, .Background)

		if string(cstring(&loaded_background[0])) != path {
			video.impl.destroy_texture(ui.background)
			if path != "" {
				ui.background, ui.background_width, ui.background_height, _ = 
					video.load_texture(path)
			}
			else {
				ui.background = {}
			}
			util.copy_string_to_buf(loaded_background[:], path)
		}
	}

	_load_fonts(prefs)

	// Load default theme
	theme.load(config.get_string(prefs, .Theme))
}

/*@private
signal_handler :: proc(sig: signal.Signal) {
	if sig == .ApplyPrefs {
		_apply_prefs()
	}
}*/

bring_window_to_front :: proc(ui: ^State, win: Window) {
	ui.windows[win].bring_to_front = true
}

@private
_add_files_iterator :: proc(path: string, is_folder: bool, data: rawptr) {
	ui := cast(^State)data
	
	if is_folder {
		//util.for_each_file_in_folder(path, _add_files_iterator, data)
		path_buf: [512]u8
		util.copy_string_to_buf(path_buf[:], path)
		append(&ui.background_metadata_scan.paths, path_buf)
	}
	else {
		offset := len(ui.deferred_files.pool)
		_, err := append_string(&ui.deferred_files.pool, path)
		if err != .None {return}
		append(&ui.deferred_files.files, Offset_Length{offset = offset, length = len(path)})
	}
}

/*@private
_async_scan_thread_proc :: proc(thread_data: ^thread.Thread) {
	context.logger = log.create_console_logger()
	lib := cast(^Library) thread_data.data
	df := &this.deferred_files
	for f in df.files {
		file := transmute(string) df.pool[f.offset:][:f.length]
		library.add_file(lib, file)
		//intrinsics.atomic_exchange(&df.files_loaded, intrinsics.atomic_add(&df.files_loaded, 1));
		df.files_loaded += 1
	}

	delete(df.files)
	df.files = nil
	delete(df.pool)
	df.pool = nil
	intrinsics.atomic_store(&df.scanning, false)
	intrinsics.atomic_store(&df.files_loaded, 0)

	log.debug("Async file scan done")
}

@private
_begin_async_scan :: proc() {
	log.debug("Begin async file scan")
	this.deferred_files.scanning = true
	tp := thread.create(_async_scan_thread_proc)
	thread.start(tp)
}*/

/*@private
_begin_metadata_save_job :: proc() {
	if util.message_box(
		"Save Metadata Changes", .OkCancel,
		"Save all metadata changes to your music files? This cannot be undone."
	) {
		this.metadata_save_job = lib.save_metadata_changes_async();
	}
}*/

@private
_metadata_scan_proc :: proc(thread_info: ^thread.Thread) {
	data := cast(^_Background_Metadata_Scan) thread_info.data

	count_files :: proc(path: string) -> int {
		count: int

		iterator :: proc(path: string, is_folder: bool, data: rawptr) {
			count := cast(^int) data

			if is_folder {
				util.for_each_file_in_folder(path, iterator, data)
			}
			else {
				count^ += 1
			}
		}

		if os.is_dir(path) {
			util.for_each_file_in_folder(path, iterator, &count)
		}
		else {
			count += 1
		}

		return count
	}

	for &path_buf in data.paths {
		path := string(cstring(&path_buf[0]))
		data.input_file_count += count_files(path)
	}

	for &path_buf in data.paths {
		path := string(cstring(&path_buf[0]))
		library.scan_folder(data.exclude_path_hashes, path, &data.output)
	}
}

@private
_begin_window :: proc(ui: ^State, window: Window) -> bool {
	name: [256]u8
	info := &window_info[window]
	state := &ui.windows[window]

	fmt.bprint(name[:255], info.name, "###", info.internal_name, sep="")

	if state.bring_to_front {
		imgui.SetNextWindowFocus()
		state.bring_to_front = false
	}

	begin := imgui.Begin(cstring(&name[0]), &state.show, state.flags)
	if begin {return true}
	imgui.End()
	return false
}

show :: proc(ui: ^State, lib: ^Library, pb: ^Playback, prefs: ^config.Preferences) -> (keep_running: bool = true) {
	@static tick_last_frame: time.Tick
	@static is_first_frame := true
	delta: f32

	if is_first_frame {
		delta = 1.0/60.0
		is_first_frame = false
	}
	else {
		delta = cast(f32) time.duration_seconds(time.tick_since(tick_last_frame))
	}
	tick_last_frame = time.tick_now()

	// Layouts need to be loaded before NewFrame or else docking settings
	// aren't respected
	if ui.layout_that_we_want_to_load != nil {
		imgui.LoadIniSettingsFromMemory(cstring(&ui.layout_that_we_want_to_load[0]), len(ui.layout_that_we_want_to_load))
		if ui.free_layout_after_load {
			delete(ui.layout_that_we_want_to_load)
		}
		ui.layout_that_we_want_to_load = nil
	}

	io := imgui.GetIO()
	style := imgui.GetStyle()

	new_playlist_popup_name := cstring("New Playlist")
	ui.new_playlist_popup_id = imgui.GetID(new_playlist_popup_name)

	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.DockSpaceOverViewport({}, nil, {})
	imgui.PopStyleColor()

	analysis.update(lib^, pb^, delta, 1.0/30.0)

	// Draw background
	if ui.background.id != nil {
		drawlist := imgui.GetBackgroundDrawList()
		w := f32(ui.background_width)
		h := f32(ui.background_height)
		ww := io.DisplaySize.x
		wh := io.DisplaySize.y

		if h != wh {
			ratio := wh / h
			w = math.ceil(w * ratio)
			h = math.ceil(h * ratio)
		}

		if w < ww {
			ratio := ww / w
			w = math.ceil(w * ratio)
			h = math.ceil(h * ratio)
		}

		imgui.DrawList_AddImage(
			drawlist,
			ui.background.id,
			{0, 0},
			{w, h},
		)
	}

	// Check if there are any files queued for processing and begin processing them if
	// needed
	if len(ui.background_metadata_scan.paths) > 0 && ui.background_metadata_scan_thread == nil {
		ui.background_metadata_scan.exclude_path_hashes = slice.clone(lib.track_path_hashes[:])
		ui.background_metadata_scan.input_file_count = 0
		ui.background_metadata_scan_thread = thread.create(_metadata_scan_proc)
		ui.background_metadata_scan_thread.data = &ui.background_metadata_scan
		log.debug("Starting metadata scan")
		thread.start(ui.background_metadata_scan_thread)
	}

	if ui.background_metadata_scan_thread != nil {
		if thread.is_done(ui.background_metadata_scan_thread) {
			thread.destroy(ui.background_metadata_scan_thread)
			ui.background_metadata_scan_thread = nil
			
			library.add_tracks_from_track_data(lib, ui.background_metadata_scan.output)

			clear(&ui.background_metadata_scan.paths)
			delete(ui.background_metadata_scan.exclude_path_hashes)
			library.free_track_data(ui.background_metadata_scan.output)
		}
		else {
			if imgui.Begin("Metadata scan progress") {
				progress := f32(len(ui.background_metadata_scan.output.metadata)) / f32(ui.background_metadata_scan.input_file_count)
				imgui.Text("Processing files %d/%d",
					cast(i32) len(ui.background_metadata_scan.output.metadata),
					cast(i32) ui.background_metadata_scan.input_file_count,
				)
				imgui.ProgressBar(progress, {imgui.GetContentRegionAvail().x, 0})
			}
			imgui.End()
		}
	}

	// -------------------------------------------------------------------------
	// Drag-drop
	// -------------------------------------------------------------------------
	// @FixMe
	/*if ui.want_to_drop_platform_drag_drop_payload {
		for file in ui.platform_drag_drop_payload {
			_add_files_iterator(file, os.is_dir(file), nil)
		}
	
		//_ext_drag_drop_clear_payload()
		ui.want_to_drop_platform_drag_drop_payload = false
	}*/

	// -----------------------------------------------------------------------------
	// Hotkeys
	// -----------------------------------------------------------------------------
	if imgui.IsKeyPressed(.F1) {
		ui.show_help = !ui.show_help
	}
	
	// -----------------------------------------------------------------------------
	// Preferences
	// -----------------------------------------------------------------------------
	if ui.show_preferences {
		if imgui.Begin("Preferences", &ui.show_preferences) {
			_show_preferences_window(prefs)
		}
		imgui.End()
	}

	// -------------------------------------------------------------------------
	// Main menu bar
	// -------------------------------------------------------------------------
	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Add folders", nil, false, ui.background_metadata_scan_thread == nil) {
				util.for_each_file_in_dialog(nil, _add_files_iterator, ui, select_folders=true)
			}

			imgui.Separator()
			if imgui.MenuItem("Preferences") {
				ui.show_preferences = true
			}
			imgui.MenuItem("Minimize to tray")
			imgui.Separator()
			if imgui.MenuItem("Exit") {
				keep_running = false
			}
			imgui.EndMenu()
		}

		if imgui.BeginMenu("View") {
			for &window, window_id in window_info {
				if imgui.BeginMenu(window_category_info[window.category].name) {
					imgui.MenuItemBoolPtr(window.name, nil, &ui.windows[window_id].show)
					imgui.EndMenu()
				}
			}

			imgui.Separator()

			if imgui.BeginMenu("Layout") {
				@static new_layout_name: _Layout_Name

				if imgui.MenuItem("Default") {
					ui.layout_that_we_want_to_load = DEFAULT_LAYOUT_INI
					ui.free_layout_after_load = false
				}

				imgui.Separator()

				for &layout_name, layout_index in ui.layout_names {
					if imgui.MenuItem(cstring(&layout_name[0])) {
						_load_layout(ui, layout_index)
					}
				}

				imgui.Separator()
				imgui.InputTextWithHint("##layout_name", "Layout Name", cstring(&new_layout_name[0]), len(new_layout_name))
				if imgui.MenuItem("Save current...") {
					new_layout_index := len(ui.layout_names)
					layout_exists := false
					for &layout_name, layout_index in ui.layout_names {
						if cstring(&layout_name[0]) == cstring(&new_layout_name[0]) {
							new_layout_index = layout_index
							layout_exists = true
							break
						}
					}

					if !layout_exists {
						append(&ui.layout_names, new_layout_name)
					}

					_save_layout(ui^, new_layout_index)

					slice.fill(new_layout_name[:], 0)
				}

				imgui.EndMenu()
			}

			imgui.EndMenu()
		}

		if imgui.BeginMenu("Help") {
			if imgui.MenuItem("Manual") {
				ui.show_help = true
			}
			if imgui.MenuItem("About") {
				ui.show_about = true
			}
			imgui.EndMenu()
		}

		when ODIN_DEBUG {
			if imgui.BeginMenu("Debug") {
				imgui.MenuItemBoolPtr("Show theme editor", nil, &ui.enable_imgui_theme_editor)
				imgui.MenuItemBoolPtr("Show ImGui demo", nil, &ui.enable_imgui_demo_window)
				imgui.EndMenu()
			}
		}

		// -----------------------------------------------------------------------------
		// Volume
		// -----------------------------------------------------------------------------
		{
			volume := playback.get_volume() * 100
			imgui.SetNextItemWidth(100)
			if imgui.SliderFloat("##volume", &volume, 0, 100, "%.0f%%") {
				playback.set_volume(volume / 100)
			}
		}

		imgui.Separator()

		// -----------------------------------------------------------------------------
		// Playback controls
		// -----------------------------------------------------------------------------
		if imgui.MenuItem(STOP_ICON) {
			playback.stop(pb)
		}

		if imgui.MenuItem(SHUFFLE_ICON, nil, pb.shuffle) {
			playback.toggle_shuffle(pb)
		}

		if imgui.MenuItem(PREV_TRACK_ICON) {
			playback.play_prev_track(pb, lib^)
		}

		if playback.is_paused(pb^) {
			if imgui.MenuItem(PLAY_ICON) {
				playback.set_paused(pb, false)
			}
		}
		else {
			if imgui.MenuItem(PAUSE_ICON) {
				playback.set_paused(pb, true)
			}
		}

		if imgui.MenuItem(NEXT_TRACK_ICON) {
			playback.play_next_track(pb, lib^)
		}
		imgui.Separator()
			
		// -----------------------------------------------------------------------------
		// Mini visualizer
		// -----------------------------------------------------------------------------
		{
			use_spectrum := config.get_property("ui_prefer_spectrum").(bool) or_else false
			if use_spectrum {
				if _show_spectrum_widget("##spectrum", {100, imgui.GetFrameHeight()}) {
					config.set_property("ui_prefer_spectrum", false)
				}
			}
			else {
				if _show_peak_meter_widget("##peak_meter", {100, 0}) {
					config.set_property("ui_prefer_spectrum", true)
				}
			}
			imgui.Separator()
		}

		// ---------------------------------------------------------------------
		// Seek bar
		// ---------------------------------------------------------------------
		{
			@static seek_target: f32
			pos := playback.get_second(pb^)
			duration := playback.get_duration(pb^)

			ch, cm, cs := util.split_seconds(cast(i32) pos)
			dh, dm, ds := util.split_seconds(cast(i32) duration)

			imgui.Text("%02d:%02d:%02d/%02d:%02d:%02d", ch, cm, cs, dh, dm, ds)
			
			frac := f32(pos) / f32(duration)
			if _show_scrubber_widget("##position", &frac, 0, 1) {
				seek_target = frac
			}

			if imgui.IsItemDeactivated() {
				playback.seek(pb, int(seek_target * f32(duration)))
			}
		}

		imgui.EndMainMenuBar()
	}

	// -------------------------------------------------------------------------
	// Help
	// -------------------------------------------------------------------------
	if ui.show_help {
		if imgui.Begin("Manual", &ui.show_help) {
			_show_help_window()
		}
		imgui.End()
	}

	if ui.show_about {
		if imgui.Begin("About", &ui.show_about) {
			_show_about_window()
		}
		imgui.End()
	}

	// -----------------------------------------------------------------------------
	// Show windows
	// -----------------------------------------------------------------------------
	/*for &window in window_info {
		if window.bring_to_front {
			window.bring_to_front = false
			window.show = true
			log.debug("Bring to front", window.name)
			imgui.SetNextWindowFocus()
		}

		if !window.show || window.show_proc == nil {continue}

		name_buf: [128]u8
		fmt.bprint(name_buf[:127], window.name, "###", window.internal_name, sep="")

		if imgui.Begin(cstring(&name_buf[0]), &window.show, window.flags) {
			window.show_proc()
		}
		imgui.End()
	}*/

	for window_id in Window {
		switch window_id {
			case .Library: {
				if _begin_window(ui, .Library) {
					_show_library_window(ui, lib, pb)
					imgui.End()
				}
			}
			case .Metadata: {
				if _begin_window(ui, .Metadata) {
					_show_metadata_window(&ui.metadata, lib^, pb.playing_track)
					imgui.End()
				}
			}
			case .Queue: {
				if _begin_window(ui, .Queue) {
					_show_queue_window(ui, lib, pb)
					imgui.End()
				}
			}
			case .Navigation: {
				if _begin_window(ui, .Navigation) {
					_show_navigation_window(ui, lib, pb)
					imgui.End()
				}
			}
			case .Artists: {
				if _begin_window(ui, .Artists) {
					_show_playlist_group_window(lib^, pb, lib.artists, &ui.artists_window)
					imgui.End()
				}
			}
			case .Albums: {
				if _begin_window(ui, .Albums) {
					_show_playlist_group_window(lib^, pb, lib.albums, &ui.albums_window)
					imgui.End()
				}
			}
			case .Genres: {
				if _begin_window(ui, .Genres) {
					_show_playlist_group_window(lib^, pb, lib.genres, &ui.genres_window)
					imgui.End()
				}
			}
			case .Folders: {
				if _begin_window(ui, .Folders) {
					_show_playlist_group_window(lib^, pb, lib.folders, &ui.folders_window)
					imgui.End()
				}
			}
			case .Playlist: {		
				if _begin_window(ui, .Playlist) {
					_show_selected_playlist_window(ui, lib, pb)
					imgui.End()
				}
			}
			case .PlaylistTabs: {
				if _begin_window(ui, .PlaylistTabs) {
					_show_playlist_tabs_window(ui, lib, pb)
					imgui.End()
				}
			}
			case .PeakMeter: {
				if _begin_window(ui, .PeakMeter) {
					_show_peak_window()
					imgui.End()
				}
			}
			case .Spectrum: {
				if _begin_window(ui, .Spectrum) {
					_show_spectrum_window()
					imgui.End()
				}
			}
			case .EditMetadata: {
				if _begin_window(ui, .EditMetadata) {
					_show_metadata_editor(lib^, ui.selection[:])
					imgui.End()
				}
			}
			case .ThemeEditor: {
				if _begin_window(ui, .ThemeEditor) {
					_show_theme_editor_window(&ui.windows[.ThemeEditor])
					imgui.End()
				}
			}
			case .WavePreview: {
				if _begin_window(ui, .WavePreview) {
					_show_wave_preview_window(pb)
					imgui.End()
				}
			}
			case .ReplaceMetadata: {
				if _begin_window(ui, .ReplaceMetadata) {
					_show_metadata_replacement_window(lib^, ui.selection[:])
					imgui.End()
				}
			}
		}
	}

	// -------------------------------------------------------------------------
	// New playlist popup
	// -------------------------------------------------------------------------
	imgui.SetNextWindowSize({400, 150})
	if imgui.BeginPopupModal(new_playlist_popup_name, nil, {.NoResize}) {
		defer imgui.EndPopup()

		@static input: [128]u8
		@static error: library.Add_Playlist_Error
		commit := false

		commit |= imgui.InputText("Name your playlist", cstring(raw_data(input[:])), 128, {.EnterReturnsTrue})
		commit |= imgui.Button("Create")
		imgui.SameLine()
		if imgui.Button("Cancel") {imgui.CloseCurrentPopup()}

		if error != .None {
			error_str: cstring = error == .NameExists ? "Already a playlist with that name" : "Name is reserved"
			imgui.Text(error_str)
		}

		if commit {
			cstr := cstring(raw_data(input[:]))
			name := string(input[:len(cstr)])
			_, error = library.add_playlist(lib, name)

			if error == .None {
				imgui.CloseCurrentPopup()
				error = .None
				for &b in input {b = 0}
			}
		}
	}

	if ui.enable_imgui_theme_editor {
		imgui.ShowStyleEditor()
	}

	if ui.enable_imgui_demo_window {
		imgui.ShowDemoWindow(&ui.enable_imgui_demo_window)
	}

	return
}

@private
_show_library_window :: proc(ui: ^State, lib: ^Library, pb: ^Playback) {
	playlist := &lib.library
	_show_playlist_track_table(ui, lib, pb, playlist, &ui.library_window)
}

@private
_handle_select_track :: proc(ui: ^State, playlist_id: Playlist_ID, from: []Track_ID, track_id: Track_ID, force_no_clear := false) {
	if ui.selection_playlist_id != playlist_id {
		clear(&ui.selection)
		ui.selection_playlist_id = playlist_id
	}

	selected := slice.contains(ui.selection[:], track_id)

	if imgui.IsKeyDown(.ImGuiMod_Shift) {
		if track_index, found := slice.linear_search(from, track_id); found {
			range_start := 0

			for sel in ui.selection {
				index := slice.linear_search(from, sel) or_continue
				if index < track_index {range_start = max(range_start, index)}
			}

			for sel in from[range_start:track_index] {
				if !slice.contains(ui.selection[:], sel) {
					append(&ui.selection, sel)
				}
			}

			append(&ui.selection, track_id)
		}
	}
	else {
		if !imgui.IsKeyDown(.ImGuiMod_Ctrl) {
			if !(force_no_clear && selected) {
				clear(&ui.selection)
				append(&ui.selection, track_id)
			}
			if !selected {append(&ui.selection, track_id)}
		}
		else if !selected {append(&ui.selection, track_id)}
	}
}

@private
_show_track_generic_context_menu_items :: proc(ui: ^State, lib: ^Library, from_playlist: Playlist_ID, track_id: Track_ID, selection: []Track_ID) {
	track := library.get_track_info(lib^, track_id)
	if imgui.BeginMenu("Add to playlist") {
		for &target_playlist in lib.playlists {
			if target_playlist.id == from_playlist {continue}
			if imgui.MenuItem(target_playlist.name) {
				library.playlist_add_tracks(&target_playlist, selection)
				library.save_playlist(lib, target_playlist.id)
			}
		}
		imgui.EndMenu()
	}

	if imgui.BeginMenu("Go to") {
		if imgui.MenuItem("Artist") {
			ui.artists_window.selected_playlist_id = library.get_playlist_group_id_from_name(string(track.artist))
			bring_window_to_front(ui, .Artists)
		}

		if imgui.MenuItem("Album") {
			ui.albums_window.selected_playlist_id = library.get_playlist_group_id_from_name(string(track.album))
			bring_window_to_front(ui, .Albums)
		}

		if imgui.MenuItem("Genre") {
			ui.genres_window.selected_playlist_id = library.get_playlist_group_id_from_name(string(track.genre), case_insensitive=true)
			bring_window_to_front(ui, .Genres)
		}

		imgui.EndMenu()
	}
}

@private
_show_playlist_track_table :: proc(ui: ^State, lib: ^Library, pb: ^Playback, playlist: ^library.Playlist, state: ^_Playlist_Window, no_remove := false) {
	want_remove_selection: bool
	apply_filter: bool
	use_filter: bool

	// Filter
	{
		if imgui.InputTextWithHint("##playlist_filter", "Filter", cstring(raw_data(state.filter[:])), len(state.filter)) {
			apply_filter = true
		}

		apply_filter |= playlist.id != state.playlist_id
		apply_filter |= len(playlist.tracks) != state.length_of_playlist_when_filtered
		use_filter = state.filter[0] != 0

		if apply_filter && use_filter {
			filter := string(cstring(&state.filter[0]))
			state.filtered_tracks = library.filter_tracks(lib^, playlist.tracks[:], filter)
			state.length_of_playlist_when_filtered = len(playlist.tracks)
		}
	}

	state.playlist_id = playlist.id

	table := _Track_Table_Iterator {
		tracks = use_filter ? state.filtered_tracks : playlist.tracks[:],
		selection = ui.selection_playlist_id == playlist.id ? ui.selection[:] : nil,
	}

	if len(table.tracks) == 0 {
		imgui.TextDisabled("Playlist is empty")
		return
	}

	if _begin_track_table(lib^, &table, "##tracks") {
		if _track_table_update_sort_spec(&state.sort_spec) {
			library.sort_tracks(lib^, playlist.tracks[:], state.sort_spec)
		}

		for _show_next_track_table_row(lib^, pb^, &table) {
			if !table.visible {continue}

			track := table.track
			left_clicked := imgui.IsItemClicked(.Left)
			middle_clicked := imgui.IsItemClicked(.Middle)
			right_clicked := imgui.IsItemClicked(.Right)

			if left_clicked || middle_clicked {
				_handle_select_track(ui, playlist.id, table.tracks, table.track)
			}

			if middle_clicked || (left_clicked && imgui.IsMouseDoubleClicked(.Left)) {
				playback.play_playlist(pb, lib^, playlist^, table.track)
			}

			if imgui.BeginPopupContextItem() {
				_handle_select_track(ui, playlist.id, table.tracks, table.track, true)
				_show_track_generic_context_menu_items(ui, lib, playlist.id, track, table.selection)

				if imgui.MenuItem("Add to queue") {
					playback.append_to_queue(pb, ui.selection[:])
				}

				if imgui.MenuItem("Play") {
					playback.play_track_array(pb, lib^, ui.selection[:])
				}

				if !no_remove {
					imgui.Separator()

					if imgui.MenuItem("Remove") {
						want_remove_selection = true
					}
				}

				imgui.EndPopup()
			}
		}
		_end_track_table(&table)

		if want_remove_selection {
			library.playlist_remove_tracks(playlist, table.selection)
			library.save_playlist(lib, playlist.id)
		}
	}
}

@private
_show_queue_window :: proc(ui: ^State, lib: ^Library, pb: ^Playback) {
	@static sort_spec: library.Track_Sort_Spec
	want_remove_selection: bool

	queue_id := Playlist_ID{user = max(u32)}
	table := _Track_Table_Iterator {
		tracks = pb.queue[:],
		selection = ui.selection_playlist_id == queue_id ? ui.selection[:] : nil,
	}

	if _begin_track_table(lib^, &table, "##queue") {
		if _track_table_update_sort_spec(&sort_spec) {
			playback.sort_queue(pb^, lib^, sort_spec)
		}

		for _show_next_track_table_row(lib^, pb^, &table) {
			if !table.visible {continue}
			track := table.track
			left_clicked := imgui.IsItemClicked(.Left)
			middle_clicked := imgui.IsItemClicked(.Middle)
			right_clicked := imgui.IsItemClicked(.Right)

			if left_clicked || middle_clicked || right_clicked {
				_handle_select_track(ui, queue_id, table.tracks, table.track)
			}

			if middle_clicked || (left_clicked && imgui.IsMouseDoubleClicked(.Left)) {
				playback.play_track_at_position(pb, lib^, table._pos-1)
			}

			if imgui.BeginPopupContextItem() {
				_show_track_generic_context_menu_items(ui, lib, queue_id, track, table.selection)
				imgui.Separator()

				if imgui.MenuItem("Remove") {
					want_remove_selection = true
				}

				imgui.EndPopup()
			}
		}

		_end_track_table(&table)
	}
}

@private
_show_selected_playlist_window :: proc(ui: ^State, lib: ^Library, pb: ^Playback) {
	@static state: _Playlist_Window

	playlist := library.get_playlist(lib, ui.selected_playlist)
	if ui.selected_playlist.user == 0 || playlist == nil {
		imgui.TextDisabled("No playlist selected")
		return
	}
			
	imgui.TextUnformatted(playlist.name)
	imgui.Separator()
	_show_playlist_track_table(ui, lib, pb, playlist, &state)
}

@private
_show_navigation_window :: proc(ui: ^State, lib: ^Library, pb: ^Playback) {
	playlists := lib.playlists[:]
	queued_playlist_id := pb.queued_playlist
	delete_playlist_id: Playlist_ID

	table_flags := imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner

	setup_columns :: proc() {		
		imgui.TableSetupColumn("Name", {.WidthStretch}, 0.8)
		imgui.TableSetupColumn("No. Tracks", {.WidthStretch}, 0.2)
	}

	if imgui.BeginTable("nav_table", 2, imgui.TableFlags_BordersInner) {
		defer imgui.EndTable()

		setup_columns()

		row :: proc(ui: ^State, name: cstring, window: Window, length: int) {
			imgui.TableNextRow()

			if imgui.TableSetColumnIndex(1) && length != 0 {
				imgui.TextDisabled("%d", cast(i32) length)
			}

			if imgui.TableSetColumnIndex(0) {
				if imgui.Selectable(name, false, {.SpanAllColumns}) {
					bring_window_to_front(ui, window)
				}
			}
		}
		
		row(ui, "Library", .Library, len(lib.library.tracks))
		if imgui.IsItemClicked(.Middle) {
			playback.play_playlist(pb, lib^, lib.library)
		}
		row(ui, "Artists", .Artists, len(lib.artists.playlists))
		row(ui, "Albums", .Albums, len(lib.albums.playlists))
		row(ui, "Folders", .Folders, len(lib.folders.playlists))
	}

	imgui.SeparatorText("Your Playlists")

	if imgui.Button("+ New playlist...") {
		imgui.OpenPopupID(ui.new_playlist_popup_id)
	}

	if imgui.BeginTable("playlist_table", 2, table_flags|imgui.TableFlags_ScrollY) {
		defer imgui.EndTable()

		setup_columns()

		for &p, index in playlists {
			imgui.TableNextRow()

			if imgui.TableSetColumnIndex(0) {
				if imgui.Selectable(p.name, p.id == ui.selected_playlist, {.SpanAllColumns}) {
					bring_window_to_front(ui, .Playlist)
					ui.selected_playlist = p.id
				}

				if p.id == queued_playlist_id {
					imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(theme.custom_colors[.PlayingHighlight]))
				}
				
				if imgui.BeginPopupContextItem() {
					if imgui.MenuItem("Delete") {
						message_buf: [256]u8
						message := fmt.bprint(message_buf[:], "Delete playlist ", p.name, "? This cannot be undone.", sep="")
						if util.message_box("Confirm delete", .OkCancel, message) {
							delete_playlist_id = p.id
						}
					}
					imgui.EndPopup()
				}
			}

			if imgui.TableSetColumnIndex(1) {
				imgui.TextDisabled("%d", cast(i32) len(p.tracks))
			}
		}
	}

	if delete_playlist_id.user != 0 {
		library.delete_playlist(lib, delete_playlist_id)
	}
}

@private
_show_playlist_group_window :: proc(lib: Library, pb: ^Playback, list: library.Playlist_List, state: ^Playlist_Group_Window) {
	if !imgui.BeginTable(
		"##layout_table", 2, 
		imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchSame|imgui.TableFlags_NoHostExtendX
	) {return}
	defer imgui.EndTable()
	
	imgui.TableNextRow()
	if imgui.TableSetColumnIndex(0) {
		index_of_queued_playlist := -1
		queued_playlist_id := pb.queued_playlist
		for p, index in list.playlists {
			if p.id == queued_playlist_id {
				index_of_queued_playlist = index
				break
			}
		}

		if _begin_playlist_table("##playlist_table") {
			if _playlist_table_update_sort_spec(&state.sort_spec) {
				library.sort_playlist_list(list, state.sort_spec)
			}

			for playlist in list.playlists {
				if _playlist_table_row(playlist, false, queued_playlist_id == playlist.id) {
					state.selected_playlist_id = playlist.id
				}

				if imgui.IsItemClicked(.Middle) || (imgui.IsMouseClicked(.Left) && imgui.IsMouseDoubleClicked(.Left)) {
					playback.play_playlist(pb, lib, playlist)
					state.selected_playlist_id = playlist.id
				}
			}

			_end_playlist_table()
		}
	}
		
	if state.selected_playlist_id != nil && imgui.TableSetColumnIndex(1) {
		window_focused := imgui.IsWindowFocused()
		playlist: library.Playlist
		found_playlist: bool
		
		for &p in list.playlists {
			if p.id == state.selected_playlist_id.? {
				playlist = p
				found_playlist = true
				break
			}
		}
		
		if !found_playlist {
			state.selected_playlist_id = nil
			return
		}
		
		imgui.Separator()

		table := _Track_Table_Iterator {
			tracks = playlist.tracks[:],
		}

		if _begin_track_table(lib, &table, "##playlist_group_tracks") {
			for _show_next_track_table_row(lib, pb^, &table) {
				if imgui.IsItemClicked(.Middle) || (imgui.IsItemClicked(.Left) && imgui.IsMouseDoubleClicked(.Left)) {
					playback.play_playlist(pb, lib, playlist, table.track)
				}
			}

			_end_track_table(&table)
		}
	}
}

@private
_show_playlist_tabs_window :: proc(ui: ^State, lib: ^Library, pb: ^Playback) {
	playlists := lib.playlists[:]
	@static state: _Playlist_Window

	if imgui.BeginTabBar("##playlists") {
		for &playlist in playlists {
			if imgui.BeginTabItem(playlist.name) {
				_show_playlist_track_table(ui, lib, pb, &playlist, &state)
				imgui.EndTabItem()
			}
		}
	}
	imgui.EndTabBar()
}

@private
_show_metadata_window :: proc(state: ^_Metadata_Window, lib: Library, display_track: Track_ID) {
	if state.track != display_track {
		state.track = display_track

		if state.thumbnail.id != nil {
			video.impl.destroy_texture(state.thumbnail)
			state.thumbnail = {}
		}

		if state.comment != nil {
			delete(state.comment)
			state.comment = nil
		}

		if display_track != 0 {
			state.thumbnail, _ = library.load_track_thumbnail(lib, display_track)
			state.comment = library.load_track_comment(lib, display_track)
		}
	}

	if display_track == 0 {
		imgui.TextDisabled("No track")
		return
	}

	avail_size := imgui.GetContentRegionAvail()
	if state.thumbnail.id != nil {
		imgui.PushStyleVarImVec2(.FramePadding, {0, 0})
		defer imgui.PopStyleVar()

		imgui.ImageButton("##thumbnail", state.thumbnail.id, {avail_size.x, avail_size.x})
		// @TODO Add right-click context menu
		/*if imgui.BeginPopupContextItem() {
			_show_track_base_context_menu(lib, 0, playing_track)
			imgui.EndPopup()
		}*/
	}
	else {
		imgui.InvisibleButton("##thumbnail", {avail_size.x, avail_size.x})
		/*if imgui.BeginPopupContextItem() {
			_show_track_base_context_menu(0, playing_track)
			imgui.EndPopup()
		}*/
	}

	imgui.Separator()

	track := library.get_track_info(lib, display_track)
	hours, minutes, seconds := util.split_seconds(cast(i32) track.duration_seconds)

	if imgui.BeginTable("Metadata Table", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("Type", {.WidthStretch}, 0.2)
		imgui.TableSetupColumn("Value", {.WidthStretch}, 0.8)

		row :: proc(name, value: cstring) {
			if len(value) > 0 {
				imgui.TableNextRow()
				imgui.TableSetColumnIndex(0)
				imgui.TextDisabled(name)
				imgui.TableSetColumnIndex(1)
				imgui.TextUnformatted(value)
			}
		}

		row_int :: proc(name: cstring, value: int) {
			if value != 0 {
				imgui.TableNextRow()
				imgui.TableSetColumnIndex(0)
				imgui.TextDisabled(name)
				imgui.TableSetColumnIndex(1)
				imgui.Text("%d", cast(i32) value)
			}
		}

		row("Title", track.title)
		row("Artist", track.artist)
		row("Album", track.album)
		row("Genre", track.genre)
		row_int("Track", track.track_number)
		row_int("Year", track.year)

		imgui.EndTable()
	}

	
	if state.comment != nil {
		imgui.Separator()
		imgui.TextWrapped(state.comment)
	}
}

@private
_show_metadata_replacement_window :: proc(lib: Library, selection: []Track_ID) {
	@static replace_with: [128]u8
	@static to_replace: [128]u8

	@static
	state: struct {
		replace_title: bool,
		replace_artist: bool,
		replace_album: bool,
		replace_genre: bool,
		in_selection: bool,
	} = {
		replace_title = true,
		replace_artist = true,
		replace_album = true,
		replace_genre = true,
		in_selection = false,
	}

	imgui.InputText("Replace", cstring(&to_replace[0]), auto_cast len(to_replace))
	imgui.InputText("With", cstring(&replace_with[0]), auto_cast len(replace_with))

	imgui.Checkbox("Replace title", &state.replace_title)
	imgui.Checkbox("Replace artist", &state.replace_artist)
	imgui.Checkbox("Replace album", &state.replace_album)
	imgui.Checkbox("Replace genre", &state.replace_genre)
	imgui.Checkbox("In selection", &state.in_selection)

	if imgui.Button("Replace metadata") {
		mask: bit_set[library.Metadata_Component]
		if state.replace_title {mask |= {.Title}}
		if state.replace_artist {mask |= {.Artist}}
		if state.replace_album {mask |= {.Album}}
		if state.replace_genre {mask |= {.Genre}}

		filter: []Track_ID = state.in_selection ? selection[:] : nil
		repl := library.Metadata_Replacement {
			replace = string(cstring(&to_replace[0])),
			with = string(cstring(&replace_with[0])),
			replace_mask = {.Artist},
		}

		replaced_count := library.perform_metadata_replacement(lib, repl, filter)
		if replaced_count > 0 {
			message_buf: [1024]u8
			message := fmt.bprint(
				message_buf[:], "Metadata was changed in", replaced_count, "tracks.",
				"These changes were not saved to the files,",
				"but can be seen in your library and will persist until the library file is deleted.",
				"To make the changes permanent, go Library -> Save metadata changes."
			)
			util.message_box("Metadata Replacement", .Message, message)
		}
		else {
			util.message_box("Metadata Replacements", .Message, "No metadata was replaced")
		}
	}
}

@private
_show_theme_editor_window :: proc(window: ^_Window_State) {
	current_theme := theme.get_current()
	style := imgui.GetStyle()
	@static unsaved_changes := false
	@static name_buf: [128]u8
	name_cstring := cstring(raw_data(name_buf[:]))
	
	imgui.InputText("Theme", name_cstring, len(name_buf))
	name_string := string(name_cstring)

	imgui.SameLine()
	if imgui.BeginCombo("##theme_picker", nil, {.NoPreview}) {
		list := theme.get_list()
		
		for name in list {
			if imgui.Selectable(name, current_theme == name) {
				theme.load(string(name))
				slice.fill(name_buf[:], 0)
				copy(name_buf[:127], string(name))
				unsaved_changes = false
			}
		}
		
		imgui.EndCombo()
	}
	// Refresh themes when we open the theme selector menu
	if imgui.IsItemActivated() {
		theme.refresh_themes()
	}

	imgui.SameLine()
	if imgui.Button("Save") {
		if name_buf[0] == 0 {
			util.message_box("Name required", .Message, "Theme must have a name")
		}
		else if theme.exists(name_string) {
			message_buf: [256]u8
			message := fmt.bprint(message_buf[:], "Overwrite theme ", name_cstring, "?", sep="")
			if util.message_box("Confirm overwrite", .OkCancel, message) {
				theme.save(string(name_cstring))
				unsaved_changes = false
			}
		}
		else {
			theme.save(name_string)
			unsaved_changes = false
		}
	}

	imgui.SameLine()
	if imgui.Button("Reload") {
		theme.load(name_string)
		unsaved_changes = false
	}

	imgui.SeparatorText(build.PROGRAM_NAME)
	for col in theme.Color {
		unsaved_changes |= imgui.ColorEdit4(theme.custom_color_info[col].name, &theme.custom_colors[col])
	}

	imgui.SeparatorText("ImGui")
	for col in imgui.Col {
		if col == .COUNT {continue}
		unsaved_changes |= imgui.ColorEdit4(imgui.GetStyleColorName(col), &style.Colors[col])
	}

	if unsaved_changes {
		window.flags |= {.UnsavedDocument}
	}
	else {
		window.flags &= ~{.UnsavedDocument}
	}
}

@private
_show_preferences_window :: proc(prefs: ^config.Preferences) {
	path_input_row :: proc(prefs: ^config.Preferences, id: config.StringID, str_id: cstring, name: cstring) -> bool {
		buffer := prefs.strings[id][:]
		imgui.PushID(name)
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted(name)
		imgui.TableSetColumnIndex(1)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		commit := imgui.InputText(str_id, cstring(raw_data(buffer)), len(config.String_Buffer))
		imgui.TableSetColumnIndex(2)
		if imgui.Button("Browse") {
			_, file_picked := util.open_file_dialog(buffer)
			commit |= file_picked
		}
		imgui.PopID()

		return commit
	}

	number_input_row :: proc(prefs: ^config.Preferences, id: config.NumberID, str_id: cstring, name: cstring) -> (commit: bool) {
		value := cast(i32) prefs.numbers[id]
		imgui.PushID(name)
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted(name)
		imgui.TableSetColumnIndex(1)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		commit |= imgui.DragInt(
			str_id, &value, 0.1,
			auto_cast config.NUMBER_INFO[id].min,
			auto_cast config.NUMBER_INFO[id].max
		)
		imgui.PopID()
		if commit {prefs.numbers[id] = cast(int) value}
		return
	}

	string_choice_row :: proc(prefs: ^config.Preferences, id: config.StringID, choices: []cstring, name: cstring) -> (commit: bool) {
		value := prefs.strings[id][:]
		imgui.PushID(name)
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted(name)
		imgui.TableSetColumnIndex(1)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		if imgui.BeginCombo("##combo", cstring(raw_data(value))) {
			for choice in choices {
				if imgui.MenuItem(choice) {
					util.copy_cstring(value, choice)
					commit = true
				}
			}
			imgui.EndCombo()
		}
		imgui.PopID()
		return
	}

	choice_row :: proc(prefs: ^config.Preferences, id: config.ChoiceID, name: cstring) -> (commit: bool) {
		info := config.CHOICE_INFO[id]
		value := prefs.choices[id]
		current_choice_name: cstring

		for choice in info.values {
			if choice.value == value {
				current_choice_name = choice.name
				break
			}
		}

		imgui.PushID(name)
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted(name)
		imgui.TableSetColumnIndex(1)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		if imgui.BeginCombo("##combo", current_choice_name) {
			for choice in info.values {
				if imgui.MenuItem(choice.name) {
					prefs.choices[id] = choice.value
					commit = true
				}
			}
			imgui.EndCombo()
		}
		imgui.PopID()

		return
	}

	// @FixMe
	/*select_device_row :: proc(pb: ^Playback) -> (changes: bool) {
		imgui.PushID("##audio_device")
		imgui.TableNextRow()
		
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted("Device")
		
		imgui.TableSetColumnIndex(1)
		pref_value := string(cstring(&prefs.prefs.strings[.PlaybackDevice][0]))
		current_device := pb.current_device
		combo_preview := pref_value != "" ? cstring(&current_device.name[0]) : "(Default)"

		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		if imgui.BeginCombo("##device_combo", combo_preview) {
			imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
			if imgui.MenuItem("Use default") {
				slice.fill(prefs.prefs.strings[.PlaybackDevice][:], 0)
				changes = true
			}
			imgui.PopStyleColor()

			imgui.Separator()

			for &device, index in pb.devices {
				if imgui.MenuItem(cstring(&device.name[0])) {
					playback.set_audio_device_index(pb, index)
					util.copy_cstring(prefs.prefs.strings[.PlaybackDevice][:], cstring(&device.id[0]))
					changes = true
				}
			}
	
			imgui.EndCombo()
		}

		imgui.TableSetColumnIndex(2)
		if imgui.Button("Refresh") {
			playback.refresh_audio_devices(pb)
		}

		imgui.PopID()

		return
	}*/

	begin_table :: proc(name: cstring) -> bool {
		imgui.SeparatorText(name)
		if imgui.BeginTable(name, 3, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_RowBg) {
			imgui.TableSetupColumn("name", {}, 0.3)
			imgui.TableSetupColumn("value", {}, 0.6)
			imgui.TableSetupColumn("button", {}, 0.1)
			return true
		}

		return false
	}

	end_table :: proc() {imgui.EndTable()}

	changes := false

	if begin_table("UI") {
		changes |= path_input_row(prefs, .Background, "##background", "Background")
		changes |= path_input_row(prefs, .Font, "##font", "Font")
		changes |= number_input_row(prefs, .FontSize, "##font_size", "Font size")
		changes |= number_input_row(prefs, .IconSize, "##icon_size", "Icon size")
		changes |= string_choice_row(prefs, .Theme, theme.get_list(), "Theme")
		changes |= choice_row(prefs, .ClosePolicy, "Close policy")
		end_table()
	}
	
	when ODIN_OS == .Windows {
		if begin_table("Windows") {
			changes |= choice_row(prefs, .EnableWindowsMediaControls, "Enable Windows media controls")
			imgui.SetItemTooltip("(Requires restart)")
			end_table()
		}
	}

	if changes {
		prefs.dirty = true
	}
}

@private
_show_help_window :: proc() {
	imgui.SeparatorText("Hotkeys")

	if imgui.BeginTable("Hotkey Table", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("Action")
		imgui.TableSetupColumn("Chord")

		row :: proc(action, chord: cstring) {
			imgui.TableNextRow()
			imgui.TableSetColumnIndex(0)
			imgui.TextUnformatted(action)
			imgui.TableSetColumnIndex(1)
			imgui.TextUnformatted(chord)
		}

		row("Toggle this window", "F1")
		row("Refresh preferences", "Ctrl + Shift + R")
		row("Select whole playlist", "Ctrl + A")
		row("Play selection", "Ctrl + Q")
		row("Jump to playing track", "Ctrl + Space")

		imgui.EndTable()
	}
}

// =============================================================================
// Action handling
// =============================================================================

/*@private
_get_selected_tracks_in_playlist :: proc(playlist: lib.Playlist) -> (tracks: [dynamic]lib.Track_ID) {
	for track in playlist.tracks {
		if _is_track_selected(track) {
			append(&tracks, track)
		}
	}

	return tracks
}*/

// Handles behaviour that is shared across all playlists
/*@private
_handle_base_track_table_action :: proc(action: Track_Table_Action, playlist: ^lib.Playlist) {
	ctrl_is_down := imgui.IsKeyDown(.ImGuiMod_Ctrl)
	altered := false

	if action.select_all {
		_clear_selection()
		
		if playlist.filter_hash != 0 {
			for track_index in playlist.filter_tracks {
				append(&this.selection, playlist.tracks[track_index])
			}
		}
		else {
			for track in playlist.tracks {
				append(&this.selection, track)
			}
		}
	}

	if action.select_track != nil {
		track_id := playlist.tracks[action.select_track.?]
		already_selected := _is_track_selected(track_id)

		if imgui.IsKeyDown(.ImGuiMod_Shift) {
			if playlist.filter_hash != 0 {
				_extend_track_selection_with_filter_to(playlist^, action.select_track.?, 
					!ctrl_is_down, playlist.filter_tracks[:])
			}
			else {
				_extend_track_selection_to(playlist^, action.select_track.?, !ctrl_is_down)
			}
		}
		else {
			if !ctrl_is_down {_clear_selection()}
			append(&this.selection, playlist.tracks[action.select_track.?])
		}
	}

	selected_tracks := _get_selected_tracks_in_playlist(playlist^)
	defer delete(selected_tracks)

	if action.add_to_queue {
		playback.append_to_queue(selected_tracks[:])
	}

	if action.play_selection {
		playback.play_track_array(selected_tracks[:])
	}
	
	if action.remove {
		_remove_selection_from_playlist(playlist)
		altered = true
	}

	
	if action.add_selection_to_playlist {
		altered = true
		_add_selection_to_playlist(playlist)
	}
	
	if action.drag_drop_payload != nil {
		altered = true
		lib.playlist_add_tracks(playlist, action.drag_drop_payload)
		delete(action.drag_drop_payload)
	}
	
	if altered && playlist.id != 0 {
		lib.save_playlist(playlist.id)
	}
	
	if action.sort_spec != nil {
		spec := action.sort_spec.?
		playlist.sort_metric = spec.metric
		playlist.sort_order = spec.order
		lib.sort_playlist(playlist)
	}

	lib.update_playlist_filter(playlist, action.filter, action.filter_hash)
}*/

/*@private
_handle_playlist_playback_action :: proc(action: Track_Table_Action, playlist: lib.Playlist) {
	ctrl_is_down := imgui.IsKeyDown(.ImGuiMod_Ctrl)
	if action.play_track != nil {
		track := playlist.tracks[action.play_track.?]
		if !_is_track_selected(track) {
			if !ctrl_is_down {_clear_selection()}
			append(&this.selection, track)
		}
		
		playback.play_playlist(playlist, track, true)
	}
}*/

/*@private
_handle_queue_playback_action :: proc(action: Track_Table_Action, playlist: lib.Playlist) {
	if action.play_track != nil {
		playback.play_track_at_position(action.play_track.?)
	}
}*/

// =============================================================================
// Drag-drop
// =============================================================================

/*@private
_ext_drag_drop_clear_payload :: proc() {
	for s in this.platform_drag_drop_payload {
		delete(s)
	}

	delete(this.platform_drag_drop_payload)
	this.platform_drag_drop_payload = nil
}

@private
_ext_drag_drop_add_file :: proc "c" (path: cstring) {
	context = this.ctx
	log.debug(path)
	append(&this.platform_drag_drop_payload, strings.clone_from_cstring(path))
}

@private
_ext_drag_drop_cancel :: proc "c" () {
	context = this.ctx
	log.debug()

	_ext_drag_drop_clear_payload()
}

@private
_ext_drag_drop_drop :: proc "c" () {
	context = this.ctx
	io := imgui.GetIO()
	log.debug()
	
	// Does this need to be done on Linux too?
	// Windows eats the mouse release event when you finish dragging
	/*when ODIN_OS == .Windows {
		imgui.IO_AddMouseButtonEvent(io, auto_cast imgui.MouseButton.Left, false);
	}*/

	this.want_to_drop_platform_drag_drop_payload = true
}

@private
_ext_drag_drop_begin :: proc "c" () {
	context = this.ctx
	io := imgui.GetIO()
	log.debug()
	
	// Need to tell ImGui that left mouse is down so drag-drop can work
	//imgui.IO_AddMouseButtonEvent(io, auto_cast imgui.MouseButton.Left, true);
}

@private
_ext_drag_drop_mouse_over :: proc "c" (x, y: f32) {
	context = this.ctx
	io := imgui.GetIO()
	log.debug(x, y)

	//imgui.IO_AddMousePosEvent(io, x, y);
}*/

@private
_imgui_settings_handler_open_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, name: cstring
) -> rawptr {
	ui := cast(^State) handler.UserData
	context = ui.ctx
	name_str := string(name)
	for window, i in window_info {
		if string(window.internal_name) == name_str {
			return cast(rawptr) (cast(uintptr) i + 1)
		}
	}

	return nil
}

@private
_imgui_settings_handler_read_line_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line: cstring
) {
	ui := cast(^State) handler.UserData
	context = ui.ctx
	if entry == nil {return}

	window: Window = cast(Window) (uintptr(entry) - 1)
	if window < min(Window) || window > max(Window) {return}

	line_parts := strings.split(string(line), "=")
	if len(line_parts) < 2 {return}

	parsed, parse_ok := strconv.parse_int(line_parts[1])
	if !parse_ok {ui.windows[window].show = true}
	else {ui.windows[window].show = parsed >= 1}
}

@private
_imgui_settings_handler_write_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
) {
	ui := cast(^State) handler.UserData
	context = ui.ctx

	for window, window_id in window_info {
		imgui.TextBuffer_appendf(out_buf, "[RAT MP][%s]\n", window.internal_name)
		imgui.TextBuffer_appendf(out_buf, "Open=%u\n", cast(u32)ui.windows[window_id].show)
	}
}

// -----------------------------------------------------------------------------
// Metadata editor
// -----------------------------------------------------------------------------
@private
_show_metadata_editor :: proc(lib: Library, selection: []Track_ID) {
	if len(selection) == 0 {
		imgui.TextDisabled("No track selected")
		return
	}
	
	table_flags := imgui.TableFlags_RowBg|imgui.TableFlags_SizingStretchProp|
	imgui.TableFlags_BordersInner
	
	string_row :: proc(buf: cstring, buf_size: int, name: cstring, enable: ^bool = nil) {
		imgui.PushID(name)
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted(name)
		imgui.TableSetColumnIndex(1)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		if imgui.InputText("##text", buf, auto_cast buf_size) && enable != nil {
			enable^ = true
		}
		if enable != nil && imgui.TableSetColumnIndex(2) {
			imgui.Checkbox("##enable", enable)
			imgui.SetItemTooltip("Apply")
		}
		imgui.PopID()
	}
	
	int_row :: proc(val: ^int, name: cstring, enable: ^bool = nil) {
		val_i32 := i32(val^)
		imgui.PushID(name)
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0)
		imgui.TextUnformatted(name)
		imgui.TableSetColumnIndex(1)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		if imgui.InputInt("##number", &val_i32) {
			val^ = int(val_i32)
			if enable != nil {enable^ = true}
		}
		if enable != nil && imgui.TableSetColumnIndex(2) {
			imgui.Checkbox("##enable", enable)
			imgui.SetItemTooltip("Apply")
		}
		imgui.PopID()
	}

	if len(selection) == 1 {
		path_buf: [384]u8
		imgui.TextDisabled("Editing track %s", library.get_track_path_cstring(lib, selection[0], path_buf[:]))

		if imgui.BeginTable("##metadata_editor_table", 2, table_flags) {
			imgui.TableSetupColumn("Name", {}, 0.3)
			imgui.TableSetupColumn("Value", {}, 0.7)
	
			track := library.get_track_info(lib, selection[0])

			string_row(track.title, library.MAX_TRACK_TITLE_LENGTH+1, "Title")
			string_row(track.artist, library.MAX_TRACK_ARTIST_LENGTH+1, "Artist")
			string_row(track.album, library.MAX_TRACK_ALBUM_LENGTH+1, "Album")
			string_row(track.genre, library.MAX_TRACK_GENRE_LENGTH+1, "Genre")
			int_row(&track.year, "Year")
			int_row(&track.track_number, "Track No.")
	
			imgui.EndTable()
		}

		/*if imgui.Button("Save to file") {
			if util.message_box("Save Metadata", .OkCancel, "Overwrite file metadata? This cannot be undone.") {
				lib.save_track_metadata(this.selection[0]);
			}
		}*/
	}
	else {
		imgui.TextDisabled("Editing %d tracks", i32(len(selection)))

		@static
		changes: struct {
			title: [library.MAX_TRACK_TITLE_LENGTH+1]u8,
			artist: [library.MAX_TRACK_ARTIST_LENGTH+1]u8,
			album: [library.MAX_TRACK_ALBUM_LENGTH+1]u8,
			genre: [library.MAX_TRACK_GENRE_LENGTH+1]u8,
			year: int,
			track: int,

			enable_title, enable_artist, enable_album, enable_genre, enable_year, enable_track: bool,
		}

		if imgui.BeginTable("##metadata_editor_table", 3, table_flags) {
			imgui.TableSetupColumn("Name", {}, 0.3)
			imgui.TableSetupColumn("Value", {}, 0.6)
			imgui.TableSetupColumn("Overwrite", {}, 0.1)

			string_row(cstring(&changes.title[0]), library.MAX_TRACK_TITLE_LENGTH+1, "Title", &changes.enable_title)
			string_row(cstring(&changes.artist[0]), library.MAX_TRACK_ARTIST_LENGTH+1, "Artist", &changes.enable_artist)
			string_row(cstring(&changes.album[0]), library.MAX_TRACK_ALBUM_LENGTH+1, "Album", &changes.enable_album)
			string_row(cstring(&changes.genre[0]), library.MAX_TRACK_GENRE_LENGTH+1, "Genre", &changes.enable_genre)
			int_row(&changes.year, "Year", &changes.enable_year)
			int_row(&changes.track, "Track No.", &changes.enable_track)
	
			imgui.EndTable()
		}

		if imgui.Button("Apply") {
			if util.message_box("Apply Changes?", .YesNo, "Apply these metadata changes to all selected tracks? This cannot be undone.") {
				for track_id in selection {
					track := library.get_raw_track_info_pointer(lib, track_id)
					if changes.enable_title {track.title = changes.title}
					if changes.enable_artist {track.artist = changes.artist}
					if changes.enable_album {track.album = changes.album}
					if changes.enable_genre {track.genre = changes.genre}
					if changes.enable_track {track.track_number = changes.track}
					if changes.enable_year {track.year = changes.year}
				}
			}
		}

		/*imgui.SameLine();
		if imgui.Button("Save all") {
			if util.message_box("Save Metadata", .OkCancel, "Overwrite file metadata for all selected tracks? This cannot be undone.") {
				for track in this.selection {
					lib.save_track_metadata(track);
				}
			}
		}*/
	}
}

// =============================================================================
// Layouts
// =============================================================================
@private
_ensure_layout_folder :: proc() {
	layouts_folder_path := filepath.join({system_paths.CONFIG_DIR, "layouts"})
	defer delete(layouts_folder_path)
	if !os.exists(layouts_folder_path) {os.make_directory(layouts_folder_path)}
}

@private
_get_layout_path :: proc(ui: State, index: int) -> string {
	name := string(cstring(&ui.layout_names[index][0]))
	return filepath.join({system_paths.CONFIG_DIR, "layouts", name})
}

@private
_set_layout_from_ini :: proc(ini: []u8) {
	imgui.LoadIniSettingsFromMemory(cstring(&ini[0]), len(ini))
}

@private
_scan_layouts :: proc(ui: ^State) {
	folder_path := filepath.join({system_paths.CONFIG_DIR, "layouts"})
	defer delete(folder_path)

	clear(&ui.layout_names)
	
	iterator :: proc(fullpath: string, is_folder: bool, data: rawptr) {
		ui := cast(^State) data
		if is_folder {return}
		filename := filepath.base(fullpath)
		name_buf: _Layout_Name
		util.copy_string_to_buf(name_buf[:], filename)
		append(&ui.layout_names, name_buf)
	}
	
	if !util.for_each_file_in_folder(folder_path, iterator, ui) {
		if !os.exists(folder_path) {os.make_directory(folder_path)}
	}
}

@private
_save_layout :: proc(ui: State, index: int) {
	path := _get_layout_path(ui, index)
	defer delete(path)
	path_cstring := strings.clone_to_cstring(path)
	defer delete(path_cstring)	
	imgui.SaveIniSettingsToDisk(path_cstring)
}

@private
_load_layout :: proc(ui: ^State, index: int) {
	path := _get_layout_path(ui^, index)
	defer delete(path)
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {return}

	ui.layout_that_we_want_to_load = data
	ui.free_layout_after_load = true
}

// =============================================================================
// Misc
// =============================================================================

@private
_show_about_window :: proc() {
	super_buf: [1024]u8
	buf := super_buf[:1023]
	imgui.SeparatorText("Build Information")
	imgui.TextUnformatted(build.PROGRAM_NAME_AND_VERSION)
	imgui.Text("Odin version: %s", strings.unsafe_string_to_cstring(ODIN_VERSION))
	imgui.Text("OS: %s", cstring(ODIN_OS_STRING))
	imgui.Text("Optimization: %s", strings.unsafe_string_to_cstring(fmt.bprint(buf, ODIN_OPTIMIZATION_MODE)))

	imgui.SeparatorText("libsndfile")
    imgui.TextUnformatted("Copyright (C) 1999-2016 Erik de Castro Lopo <erikd@mega-nerd.com>\nAll rights reserved.")
    imgui.TextLinkOpenURL("https://libsndfile.github.io/libsndfile/")
    
    imgui.SeparatorText("libsamplerate")
    imgui.TextUnformatted("Copyright (C) 2012-2016, Erik de Castro Lopo <erikd@mega-nerd.com>\nAll rights reserved.")
    imgui.TextLinkOpenURL("https://libsndfile.github.io/libsamplerate/")
    
    imgui.SeparatorText("FLAC")
    imgui.TextUnformatted("Copyright (C) 2011-2024 Xiph.Org Foundation")
    imgui.TextLinkOpenURL("https://xiph.org/flac/")
    
    imgui.SeparatorText("Opus")
    imgui.TextUnformatted(
		`Copyright (C) 2001-2023 Xiph.Org, Skype Limited, Octasic,"
        Jean-Marc Valin, Timothy B. Terriberry,"
        CSIRO, Gregory Maxwell, Mark Borgerding,"
        Erik de Castro Lopo, Mozilla, Amazon`)
    imgui.TextLinkOpenURL("https://opus-codec.org/")
    
    imgui.SeparatorText("OGG")
    imgui.TextUnformatted("Copyright (C) 2002, Xiph.org Foundation")
    imgui.TextLinkOpenURL("https://www.xiph.org/ogg/")
    
    imgui.SeparatorText("libmp3lame")
    imgui.TextUnformatted("Copyright (C) 1999 Mark Taylor")
    imgui.TextLinkOpenURL("https://www.mp3dev.org/")
    
    imgui.SeparatorText("Vorbis")
    imgui.TextUnformatted("Copyright (C) 2002-2020 Xiph.org Foundation")
    imgui.TextLinkOpenURL("https://xiph.org/vorbis/")
    
    imgui.SeparatorText("mpg123")
    imgui.TextUnformatted("Copyright (C) 1995-2020 by Michael Hipp and others,\nfree software under the terms of the LGPL v2.1")
    imgui.TextLinkOpenURL("https://mpg123.de/")
    
    imgui.SeparatorText("FreeType")
    imgui.TextUnformatted("Copyright (C) 1996-2002, 2006 by\nDavid Turner, Robert Wilhelm, and Werner Lemberg")
    imgui.TextLinkOpenURL("https://freetype.org/")
    
    imgui.SeparatorText("Brotli")
    imgui.TextUnformatted("Copyright (C) 2009, 2010, 2013-2016 by the Brotli Authors.")
    imgui.TextLinkOpenURL("https://www.brotli.org/")
    
    imgui.SeparatorText("libpng")
    imgui.TextUnformatted("Copyright (C) 1995-2024 The PNG Reference Library Authors.")
    imgui.TextLinkOpenURL("http://www.libpng.org/pub/png/libpng.html")
    
    imgui.SeparatorText("TagLib")
    imgui.TextUnformatted("Copyright (C) 2002 - 2008 by Scott Wheeler")
    imgui.TextLinkOpenURL("https://taglib.org/")
    
    imgui.SeparatorText("zlib")
    imgui.TextUnformatted("Copyright (C) 1995-2024 Jean-loup Gailly and Mark Adler")
    imgui.TextLinkOpenURL("https://www.zlib.net/")
    
    imgui.SeparatorText("bzip2")
    imgui.TextUnformatted("Copyright (C) 1996-2019 Julian R Seward")
    imgui.TextLinkOpenURL("https://sourceware.org/bzip2/")

    imgui.SeparatorText("KISS FFT")
    imgui.TextUnformatted("Copyright (c) 2003-2010 Mark Borgerding . All rights reserved.")
    imgui.TextLinkOpenURL("https://github.com/mborgerding/kissfft")
}
