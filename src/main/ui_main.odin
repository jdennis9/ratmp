#+private file
package main

import "core:slice"
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

ICON_VOLUME_OFF :: ""
ICON_VOLUME_LOW :: ""
ICON_VOLUME_MEDIUM :: ""
ICON_VOLUME_HIGH :: ""
ICON_SHUFFLE :: ""
ICON_ARROW_RIGHT :: ""
ICON_PREVIOUS_TRACK :: ""
ICON_NEXT_TRACK :: ""
ICON_PAUSE :: ""
ICON_STOP :: ""
ICON_PLAY :: ""

// -----------------------------------------------------------------------------
// Track table
// -----------------------------------------------------------------------------

_Track_Table_Row :: struct {
	album, artist, genre, title, url: string,
	duration: [9]u8,
	year: [4]u8,
	id: Track_ID,
	track_no: [3]u8,
	selected: bool,
}

_Track_Table :: struct {
	sort_spec: Maybe(Track_Sort_Spec),
	serial: uint,
	playlist_uid: UID,
	rows: [dynamic]_Track_Table_Row,
}

// -----------------------------------------------------------------------------
// Windows
// -----------------------------------------------------------------------------

_Metadata_Window :: struct {
	displayed_track: Track_ID,
	cover_art: Maybe(Texture_Handle),
	cover_width, cover_height: int,
	cover_file_size: int,
	should_crop_art: bool,
	comment: string,
}

_Playlists_Window :: struct {
	new_playlist_name: [128]u8,
	playlist_table: _Playlist_Table,
	track_table: _Track_Table,
	viewing_playlist: Maybe(Playlist_Handle),
	playlist_handles: [dynamic]Playlist_Handle,
	cant_add_playlist_reason: Cant_Add_Playlist_Reason,
}

_Track_Category_Window :: struct {
	displayed_entry_hash: u32,
	playlist_table: _Playlist_Table,
	track_table: _Track_Table,
}

// -----------------------------------------------------------------------------
// Playlist table
// -----------------------------------------------------------------------------

_Playlist_Table_Row :: struct {
	uid: UID,
	title: string,
	duration: [9]u8,
	length: [7]u8,
	tracks: []Track_ID,
	selected: bool,
	serial: uint,
}

_Playlist_Table :: struct {
	serial: uint,
	rows: [dynamic]_Playlist_Table_Row,
}

// -----------------------------------------------------------------------------
// Tracked window state
// -----------------------------------------------------------------------------

_Window_State :: struct {
	name: cstring,
	open: bool,
	bring_to_front: bool,
}

// -----------------------------------------------------------------------------
// Public types
// -----------------------------------------------------------------------------

@private
UI_Actions :: struct {
	minimize_to_tray: bool,
	exit: bool,

	debug: struct {
		force_device_reset: bool,
		load_library: bool,
		save_library: bool,
	}
}

@private
UI :: struct {
	server: ^Server,
	allocator_map: Allocator_Map,
	allocators: struct {
		per_frame: mem.Allocator,
		themes: mem.Allocator,
		fonts: mem.Allocator,
		lazy: mem.Allocator,
	},
	windows: struct {
		library: struct {
			track_table: _Track_Table,
			tracks: []Track_ID,
			serial: uint,
		},

		queue: struct {
			serial: uint,
			track_table: _Track_Table,
		},

		playlists: _Playlists_Window,

		artists: _Track_Category_Window,
		albums: _Track_Category_Window,
		genres: _Track_Category_Window,

		metadata: _Metadata_Window,
	},
	dialogs: struct {
		add_folder: File_Dialog_State,
		set_background: File_Dialog_State,
	},
	background: struct {
		texture: Maybe(Texture_Handle),
		policy: Image_Fit_Policy,
		size: [2]f32,
		path: string,
	},
	paths: struct {
		theme_folder: string,
	},
	themes: [dynamic]_Theme,
	debug: struct {
		show_style_editor: bool,
		show_demo_window: bool,
		show_memory_tracking: bool,
	},
	actions: UI_Actions,
	window_state: map[imgui.ID]_Window_State,
	sorted_window_states: []imgui.ID,
	system_fonts: []System_Font,
}

_Saved_Theme :: struct {
	name: string,
	accents: [_Theme_Accent][3]f32,
	colors: [_Theme_Color]u32,
	imgui_colors: [imgui.Col.COUNT][4]f32,
}


// -----------------------------------------------------------------------------
// Theme
// -----------------------------------------------------------------------------

_Theme_Color :: enum {
	PlayingHighlight,
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

@private
ui_init :: proc(ui: ^UI, server: ^Server) -> Error {
	ui.server = server

	// Allocators
	ui.allocators.per_frame = allocator_map_add_dynamic_arena(&ui.allocator_map, "per_frame")
	ui.allocators.fonts = allocator_map_add_dynamic_arena(&ui.allocator_map, "fonts")
	ui.allocators.themes = allocator_map_add_dynamic_arena(&ui.allocator_map, "themes", block_size=4096)
	ui.allocators.lazy = allocator_map_add_dynamic_arena(&ui.allocator_map, "lazy")

	ui_theme.imgui_colors = imgui.GetStyle().Colors
	
	// Theme defaults
	ui_theme.colors[.PlayingHighlight] = 0xff0568fc
	
	// Paths
	ui.paths.theme_folder = filepath.join({global_paths.config_dir, "themes"}, context.allocator) or_return
	ensure_dir(ui.paths.theme_folder)
	
	_load_themes(ui)
	_refresh_fonts(ui)

	ui_apply_config(ui, global_config)

	return nil
}

@private
ui_shutdown :: proc(ui: ^UI) {
}

@private
ui_apply_config :: proc(ui: ^UI, the_cfg: Config) -> Error {
	cfg := the_cfg.ui
	
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

	defer free_all(ui.allocators.per_frame)
	
	//style := imgui.GetStyle()
	//style.FontSizeBase = cfg.font_size != 0 ? clamp(f32(cfg.font_size), 8, 36) : 16
	if global_config.ui.font_size != 0 {
		imgui.PushFontFloat(nil, global_config.ui.font_size)
	}
	defer if global_config.ui.font_size != 0 do imgui.PopFont()

	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.PushStyleColor(.WindowBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor(2)

	// --------------------------------------------------------------------------
	// Add folders
	// --------------------------------------------------------------------------
	{
		results: [dynamic]Path
		defer delete(results)

		if async_file_dialog_get_results(&ui.dialogs.add_folder, &results) {
			for &p in results {
				server_queue_for_background_scan(sv, string(cstring(&p[0])))
			}
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
	// Library
	// --------------------------------------------------------------------------
	if _begin(ui, "Library###library", default_open = true) {
		w := &ui.windows.library

		if w.serial != sv.tracks_serial {
			delete(w.tracks)
			w.serial = sv.tracks_serial
			w.tracks = server_get_all_tracks(sv, context.allocator)
		}

		_track_table_show(
			ui, "##library", &w.track_table, w.serial, w.tracks, {}, 0
		)

		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Queue
	// --------------------------------------------------------------------------
	if _begin(ui, "Queue###queue", default_open = true) {
		w := &ui.windows.queue

		_track_table_show(
			ui, "##queue", &w.track_table, sv.playback.serial,
			server_get_queue(sv), {.IsQueue}, sv.queue_uid,
		)

		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Metadata
	// --------------------------------------------------------------------------
	if _begin(ui, "Metadata###metadata", default_open = true) {
		_show_metadata_window(sv, &ui.windows.metadata, sv.current_track_id)
		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Categories
	// --------------------------------------------------------------------------
	if _begin(ui, "Artists###artists") {
		_track_category_window_show_focused(ui, &ui.windows.artists, &sv.categories.artist)
		imgui.End()
	}

	if _begin(ui, "Albums###albums") {
		_track_category_window_show_focused(ui, &ui.windows.albums, &sv.categories.album)
		imgui.End()
	}

	if _begin(ui, "Genres###genres") {
		_track_category_window_show_focused(ui, &ui.windows.genres, &sv.categories.genre)
		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Theme editor
	// --------------------------------------------------------------------------
	if _begin(ui, "Theme###theme") {
		_show_theme_editor(ui)
		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Settings
	// --------------------------------------------------------------------------
	if _begin(ui, "Settings###settings") {
		global_config_dirty |= _show_settings_editor(ui)
		imgui.End()
	}

	// --------------------------------------------------------------------------
	// Playlists
	// --------------------------------------------------------------------------
	if _begin(ui, "Playlists###playlists") {
		_playlists_window_show_focused(sv, &ui.windows.playlists)
		imgui.End()
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
			if imgui.MenuItem("Change background") {
				async_file_dialog_open(&ui.dialogs.set_background, .Image, {})
			}
			imgui.EndMenu()
		}

		if imgui.BeginMenu("View") {
			for window_id in ui.sorted_window_states {
				state := (&ui.window_state[window_id]) or_continue
				if imgui.MenuItem(state.name) {
					state.bring_to_front = true
					state.open = true
				}
			}

			imgui.EndMenu()
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
		imx.text(512, track.artist, " - ", track.title)
		imgui.Separator()
		imx.text_unformatted_ex(track.album != "" ? track.album : "<no album>")

		imgui.Separator()
		if channel_string, have_channel_string := audio_channels_to_string(
			track.channels
		); have_channel_string {
			imx.text_unformatted(channel_string)
		}
		else {
			imx.text(32, track.channels, " channels")
		}

		imgui.Separator()
		imx.text(32, track.samplerate, "Hz")
		imgui.Separator()
		imx.text(32, track.bitrate_kbps, "kb/s")

		imgui.Separator()
	}

	// --------------------------------------------------------------------------
	// Scan progress
	// --------------------------------------------------------------------------
	if server_is_doing_background_scan(sv) {
		total, scanned := server_get_background_scan_progress(sv)
		progress := f32(scanned) / f32(total)
		imgui.ProgressBar(progress, {160, 0})
		imx.text(64, "Scanning metadata (", scanned, "/", total, ")")

		imgui.Separator()
	}

	return true
}

_track_table_row_from_track :: proc(
	sv: ^Server, handle: Track_ID
) -> (row: _Track_Table_Row, ok: bool) {
	track := get_track(sv, handle) or_return
	ok = true

	row.id = handle
	row.album = track.album
	row.artist = track.artist
	row.genre = track.genre
	row.title = track.title
	row.url = track.url

	{
		h, m, s := time.clock_from_seconds(auto_cast track.duration_seconds)
		fmt.bprintf(row.duration[:], "%02d:%02d:%02d", h, m, s)
	}

	if row.track_no != 0 do fmt.bprint(row.track_no[:], track.track_no)
	fmt.bprint(row.year[:], track.release_year)

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
	for row, i in t.rows {
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

	// --------------------------------------------------------------------------
	// Update if needed
	// --------------------------------------------------------------------------
	if serial != table.serial || table.playlist_uid != playlist_id {
		table.serial = serial
		table.playlist_uid = playlist_id
		clear(&table.rows)

		for track in track_ids {
			row := _track_table_row_from_track(sv, track) or_continue
			append(&table.rows, row)
		}

		if table.sort_spec != nil {
			_sort_track_table_rows(ui, table^, table.sort_spec.?)
		}
	}

	// --------------------------------------------------------------------------
	// Show
	// --------------------------------------------------------------------------
	_Column_Index :: enum {
		TrackNo,
		Title,
		Artist,
		Album,
		Genre,
		Duration,
	}

	actions: struct {
		play_track: Maybe(Track_ID),
		add_to_playlist: Maybe(Playlist_Handle),
	}

	list_clipper: imgui.ListClipper

	_check_table_size() or_return
	imgui.BeginTable(name, auto_cast len(_Column_Index),
		imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Hideable|imgui.TableFlags_Reorderable|
		imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Sortable|
		imgui.TableFlags_SortTristate|imgui.TableFlags_ScrollX
	) or_return
	defer imgui.EndTable()

	// --------------------------------------------------------------------------
	// Columns
	// --------------------------------------------------------------------------
	column_infos: [_Column_Index]struct {
		flags: imgui.TableColumnFlags,
		name: cstring,
		sort_metric: Track_Sort_Metric,
	} = {
		.Title = {name = "Title", flags = {.NoHide}, sort_metric = .Title},
		.Artist = {name = "Artist", sort_metric = .Artist},
		.Album = {name = "Album", sort_metric = .Album},
		.Genre = {name = "Genre", flags = {.DefaultHide}, sort_metric = .Genre},
		.TrackNo = {name = "Track", flags = {.DefaultHide}, sort_metric = .Track},
		.Duration = {name = "Duration", sort_metric = .Duration},
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
			s: Track_Sort_Spec

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
				_sort_track_table_rows(ui, table^, table.sort_spec.?)
				log.debug("Sorting track table", name, "with by", table.sort_spec.?.metric)
			}
		}
	}

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
					_table_select_row(table, row_index)
				}

				if imgui.BeginItemTooltip() {
					if track, got_track := get_track(sv, row.id); got_track {
						_show_track_metadata_table("##metadata", track^)
					}
					imgui.EndTooltip()
				}

				if imgui.IsItemClicked(.Middle) || imx.is_item_double_clicked() {
					actions.play_track = row.id
				}

				// Context menu
				if imgui.BeginPopupContextItem() {
					defer imgui.EndPopup()

					_table_select_row(table, row_index)

					if imgui.MenuItem("Play") {
						actions.play_track = row.id
					}

					if add_to_playlist, yes := _show_playlist_selector_menu(sv, "Add to playlist"); yes {
						actions.add_to_playlist = add_to_playlist
					}

					if .NoRemove not_in flags {
						imgui.Separator()
						imgui.MenuItem("Remove")
					}
				}

			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Artist) {
				imx.text_unformatted(row.artist)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Album) {
				imx.text_unformatted(row.album)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Genre) {
				imx.text_unformatted(row.genre)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Duration) {
				imx.text_unformatted(string_from_array(row.duration[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.TrackNo) {
				imx.text_unformatted(string_from_array(row.track_no[:]))
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

	if actions.add_to_playlist != nil {
		h := actions.add_to_playlist.?
		if playlist, ok := server_get_playlist(sv, h); ok {
			playlist_add(sv, playlist, _track_table_get_selection(table^, ui.allocators.per_frame))
		}
	}

	return true
}

_sort_track_table_rows :: proc(ui: ^UI, table: _Track_Table, spec: Track_Sort_Spec) {
	sv := ui.server
	tracks := _track_table_get_tracks(table, ui.allocators.per_frame)

	sort_tracks(sv, tracks, spec)

	for track_id, i in tracks {
		row := _track_table_row_from_track(sv, track_id) or_continue
		table.rows[i] = row
	}
}

_show_track_metadata_table :: proc(str_id: cstring, track: Track) -> bool {
	imx.begin_kv_table(str_id, imgui.TableFlags_RowBg) or_return
	defer imx.end_kv_table()

	protocol_string := [Track_Protocol]string {
		.File = "Disk"
	}

	imgui.TableSetupColumn("name", {.WidthStretch}, 0.2)
	imgui.TableSetupColumn("value", {.WidthStretch}, 0.8)
	
	if track.title != "" do imx.kv_row("Title", track.title)
	if track.artist != "" do imx.kv_row("Artist", track.artist)
	if track.album != "" do imx.kv_row("Album", track.album)
	if track.genre != "" do imx.kv_row("Genre", track.genre)
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

_show_metadata_window :: proc(sv: ^Server, w: ^_Metadata_Window, track_id: Track_ID) -> bool {
	load_cover :: proc(sv: ^Server, w: ^_Metadata_Window) -> bool {
		if w.cover_art != nil {
			texture_release(w.cover_art.?)
			w.cover_art = nil
		}

		cover_data, mime_type := find_track_thumbnail(
			sv, w.displayed_track, context.allocator
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
	_show_track_metadata_table("##metadata", md^)

	return true
}

_begin :: proc(ui: ^UI, title: cstring, default_open := false, flags: imgui.WindowFlags = {}) -> bool {
	id := imgui.GetID(title)
	state := &ui.window_state[id]
	if state == nil {
		ui.window_state[id] = _Window_State {
			name = title,
			open = default_open
		}
		state = &ui.window_state[id]

		// Sort windows by name
		delete(ui.sorted_window_states)
		ui.sorted_window_states, _ = slice.map_keys(ui.window_state)
		sort.sort(
			sort.Interface {
				collection = ui,
				len = proc(it: sort.Interface) -> int {
					return len((cast(^UI) it.collection).sorted_window_states)
				},
				less = proc(it: sort.Interface, a, b: int) -> bool {
					ui := cast(^UI) it.collection
					A := ui.window_state[ui.sorted_window_states[a]] or_return
					B := ui.window_state[ui.sorted_window_states[b]] or_return
					return strings.compare(string(A.name), string(B.name)) < 0
				},
				swap = proc(it: sort.Interface, a, b: int) {
					ui := cast(^UI) it.collection
					ui.sorted_window_states[a], ui.sorted_window_states[b] = 
						ui.sorted_window_states[b], ui.sorted_window_states[a]
				}
			},
		)

	}
	else if !state.open do return false

	if state.bring_to_front do imgui.SetNextWindowFocus()
	state.bring_to_front = false
	return imx.begin(title, &state.open, flags)
}

_track_category_window_show_playlists :: proc(
	ui: ^UI, w: ^_Track_Category_Window, cat: ^Track_Category,
) -> (shown: bool) {
	sv := ui.server
	entry_index, have_entry := track_category_find_entry_by_hash(cat, w.displayed_entry_hash)
	entry: Track_Category_Entry_Ptr

	if have_entry do entry = &cat.entries[entry_index]

	// --------------------------------------------------------------------------
	// Rebuild playlist table
	// --------------------------------------------------------------------------
	if w.playlist_table.serial != sv.track_category_serial {
		clear(&w.playlist_table.rows)
		w.playlist_table.serial = sv.track_category_serial

		for e in cat.entries {
			row := _Playlist_Table_Row {
				uid = e.uid,
				title = e.name,
				tracks = e.tracks[:],
			}

			format_duration(row.duration[:], e.duration)
			fmt.bprint(row.length[:], len(e.tracks))

			append(&w.playlist_table.rows, row)
		}
	}

	imx.title_text(cat.name)

	result, _ := _playlist_table_show("##playlists", sv, &w.playlist_table, {})
	if result.selected_row != nil {
		w.displayed_entry_hash = hash_string_32(w.playlist_table.rows[result.selected_row.?].title)
	}

	if result.played_row != nil {
		w.displayed_entry_hash = hash_string_32(w.playlist_table.rows[result.played_row.?].title)
	}

	return true
}

_track_category_window_show_tracks :: proc(
	ui: ^UI, w: ^_Track_Category_Window, cat: ^Track_Category
) -> bool {
	sv := ui.server
	entry_index, have_entry := track_category_find_entry_by_hash(cat, w.displayed_entry_hash)
	entry: Track_Category_Entry_Ptr

	if have_entry do entry = &cat.entries[entry_index]
	else {
		if w.displayed_entry_hash != 0 do w.displayed_entry_hash = 0
		imgui.TextDisabled("Select a playlist")
		return false
	}

	if entry.name == "" {
		imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
		imx.title_text(cat.name, ": None", sep="")
		imgui.PopStyleColor()
	}
	else {
		imx.title_text(cat.name, ": ", entry.name, sep="")
	}

	_track_table_show(
		ui, "##tracks", &w.track_table, sv.track_category_serial,
		entry.tracks[:], {.NoRemove}, entry.uid
	)

	return true
}

_track_category_window_show_focused :: proc(
	ui: ^UI, w: ^_Track_Category_Window, cat: ^Track_Category,
) {
	if w.displayed_entry_hash != 0 {
		if imgui.Button("Back") {
			w.displayed_entry_hash = 0
		}
		_track_category_window_show_tracks(ui, w, cat)
	}
	else {
		_track_category_window_show_playlists(ui, w, cat)
	}
}

_Playlist_Table_Actions :: struct {
	selected_row: Maybe(int),
	played_row: Maybe(int),
}

_Playlist_Table_Flag :: enum {MultiSelect}
_Playlist_Table_Flags :: bit_set[_Playlist_Table_Flag]

_playlist_table_show :: proc(
	str_id: cstring, sv: ^Server, table: ^_Playlist_Table,
	flags: _Playlist_Table_Flags,
) -> (result: _Playlist_Table_Actions, shown: bool) {
	actions: struct {
		play: Maybe(int),
		play_selection: bool,
	}

	_check_table_size() or_return
	imgui.BeginTable(
		str_id, 3,
		imgui.TableFlags_BordersInner|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Reorderable|
		imgui.TableFlags_ScrollX|imgui.TableFlags_ScrollY
	) or_return
	defer imgui.EndTable()

	imgui.TableSetupColumn("Name")
	imgui.TableSetupColumn("Duration")
	imgui.TableSetupColumn("Length")

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

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
						_table_select_row(table, row_index)
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
			}

			if imgui.TableSetColumnIndex(1) {
				imx.text_unformatted(string_from_array(row.duration[:]))
			}

			if imgui.TableSetColumnIndex(2) {
				imx.text_unformatted(string_from_array(row.length[:]))
			}
		}
	}

	if actions.play != nil {
		row := table.rows[actions.play.?]
		server_request_play_playlist(sv, row.tracks, row.uid)
		result.played_row = actions.play.?
	}

	shown = true
	return
}

_show_theme_editor :: proc(ui: ^UI) -> (changed: bool) {
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
_playlists_window_show_playlists :: proc(sv: ^Server, w: ^_Playlists_Window) -> bool {
	// --------------------------------------------------------------------------
	// Update rows
	// --------------------------------------------------------------------------
	need_update := false
	
	need_update |= sv.playlists_serial != w.playlist_table.serial
	
	if need_update {
		clear(&w.playlist_table.rows)
		clear(&w.playlist_handles)
		w.playlist_table.serial = sv.playlists_serial

		it := handle_map.iterator_make(&sv.playlists)
		for _, handle in handle_map.iterate(&it) {
			append(&w.playlist_handles, handle)
			append(&w.playlist_table.rows, _Playlist_Table_Row{})
		}
	}

	for &row, row_index in w.playlist_table.rows {
		playlist := server_get_playlist(sv, w.playlist_handles[row_index]) or_continue
		if row.serial != playlist.serial {
			row.uid = playlist.uid
			row.title = playlist.name
			row.serial = playlist.serial
			row.tracks = playlist.tracks[:]
			fmt.bprint(row.length[:], len(playlist.tracks))
			format_duration(row.duration[:], playlist.duration)
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
		w.cant_add_playlist_reason = server_can_add_playlist(
			sv, string(cstring(&w.new_playlist_name[0]))
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
		server_add_playlist(sv, string(cstring(&w.new_playlist_name[0])))
		for &r in w.new_playlist_name do r = 0
	}

	// --------------------------------------------------------------------------
	// Show table
	// --------------------------------------------------------------------------

	imx.title_text("Playlists")
	actions, _ := _playlist_table_show("##playlists", sv, &w.playlist_table, {})

	return true
}

_playlists_window_show_tracks :: proc(sv: ^Server, w: ^_Playlists_Window) -> bool {

	return true
}

_playlists_window_show_focused :: proc(sv: ^Server, w: ^_Playlists_Window) -> bool {
	if w.viewing_playlist != nil {
	}
	else {
		_playlists_window_show_playlists(sv, w)
	}

	return true
}

_show_playlist_selector_menu :: proc(
	sv: ^Server, label: cstring, exclude: Maybe(Playlist_Handle) = nil
) -> (handle: Playlist_Handle, selected: bool) {
	imgui.BeginMenu(label) or_return
	defer imgui.EndMenu()

	it := handle_map.iterator_make(&sv.playlists)
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
// Misc
// -----------------------------------------------------------------------------

_table_select_row :: proc(table: ^$T, row_index: int) {
	if !imgui.IsKeyDown(.ImGuiMod_Ctrl) {
		for &row in table.rows do row.selected = false
	}
	table.rows[row_index].selected = true
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

// -----------------------------------------------------------------------------
// Debug
// -----------------------------------------------------------------------------

_show_memory_tracking :: proc(ui: ^UI) {
	if !global_command_opts.memory_debug {
		imx.text_unformatted("Memory debugging is disabled. Launch program with -memory-debug argument.")
		return
	}

	show_info :: proc(t: mem.Tracking_Allocator) -> bool {
		imx.begin_kv_table("##kv", {}) or_return
		defer imx.end_kv_table()

		imx.kv_row("Allocation count", t.total_allocation_count)
		imx.kv_rowf("Free count", "%M", t.total_free_count)
		imx.kv_rowf("Total allocated", "%M", t.total_memory_allocated)
		imx.kv_rowf("Current allocated", "%M", t.current_memory_allocated)
		return true
	}

	show_map :: proc(m: Allocator_Map) {
		for name, entry in m {
			imx.title_text(name)
			show_info(entry.tracker^)
		}
	}

	show_map(ui.allocator_map)
}
