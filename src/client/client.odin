/*
    RAT MP - A cross-platform, extensible music player
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
package client

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:time"
import "core:os/os2"
import "core:math"
import "core:path/filepath"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:hash/xxhash"

import stbi "vendor:stb/image"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:bindings/media_controls"
import "src:build"
import "src:path_pool"
import "src:util"
import "src:sys"

import "imx"

Path :: sys.Path

Client :: struct {
	ctx: runtime.Context,
	mini_font: ^imgui.Font,
	delta: f32,

	want_quit: bool,

	// Increments every time the font is changed
	font_serial: uint,

	selected_user_playlist_id: Global_Playlist_ID,

	tick_last_frame: time.Tick,
	frame_count: int,
	library_sort_spec: server.Track_Sort_Spec,
	waveform_window: Wavebar_Window,

	background: struct {
		texture: imgui.TextureID,
		width, height: int,
	},
	show_imgui_theme_editor: bool,
	
	dialogs: struct {
		set_background: sys.File_Dialog_State,
		remove_missing_files: sys.Dialog_State,
		add_folders: sys.File_Dialog_State,
	},
		
	paths: struct {
		theme_folder: string,
		persistent_state: string,
		layout_folder: string,
		settings: string,
	},
	
	theme_names: [dynamic]cstring,
	
	loaded_fonts: []Load_Font,
	
	analysis: Analysis_State,

	window_archetypes: map[Window_Archetype_ID]Window_Archetype,
	sorted_window_archetypes: [dynamic]Window_Archetype_ID,

	windows: struct {
		settings: Settings_Editor,

		status_bar: struct {
			displayed_track_id: Track_ID,
			metadata: Track_Properties,
			artist, album, title: [64]u8
		},
		licenses: struct {
			show: bool,
		},
		about: struct {
			show: bool,
		},
	},

	enable_media_controls: bool,
	media_controls: struct {
		display_track: Track_ID,
		display_state: media_controls.State,
		enabled: bool,
	},

	layouts: Layout_Manager,

	track_drag_drop_payload: []Track_ID,

	settings: Settings,
	saved_settings: Settings,
	show_settings_window: bool,
	bring_settings_window_to_front: bool,
	want_apply_settings: bool,

	show_window_manager: bool,
	bring_window_manager_to_front: bool,

	wake_proc: proc(),

	uptime: f64,
}

init :: proc(
	client: ^Client, sv: ^Server,
	data_dir, config_dir: string,
	wake_proc: proc(),
) -> bool {
	client.ctx = context
	log.info("ImGui version:", imgui.GetVersion())

	io := imgui.GetIO()

	imx.init()

	add_window_archetype(client, LIBRARY_WINDOW_ARCHETYPE)
	add_window_archetype(client, QUEUE_WINDOW_ARCHETYPE)
	add_window_archetype(client, METADATA_WINDOW_ARCHETYPE)
	add_window_archetype(client, METADATA_EDITOR_WINDOW_ARCHETYPE)
	add_window_archetype(client, PLAYLISTS_WINDOW_ARCHETYPE)
	add_window_archetype(client, ARTISTS_WINDOW_ARCHETYPE)
	add_window_archetype(client, ALBUMS_WINDOW_ARCHETYPE)
	add_window_archetype(client, GENRES_WINDOW_ARCHETYPE)
	add_window_archetype(client, WAVEBAR_WINDOW_ARCHETYPE)
	add_window_archetype(client, SPECTRUM_WINDOW_ARCHETYPE)
	add_window_archetype(client, OSCILLOSCOPE_WINDOW_ARCHETYPE)
	add_window_archetype(client, FOLDERS_WINDOW_ARCHETYPE)
	add_window_archetype(client, THEME_EDITOR_WINDOW_ARCHETYPE)
	add_window_archetype(client, VECTORSCOPE_WINDOW_ARCHETYPE)
	add_window_archetype(client, SPECTOGRAM_WINDOW_ARCHETYPE)

	// Imgui settings handler
	{
		handler := imgui.SettingsHandler {
			ReadOpenFn = _imgui_settings_open_proc,
			ReadLineFn = _imgui_settings_read_line_proc,
			WriteAllFn = _imgui_settings_write_proc,
			UserData = client,
			TypeName = build.PROGRAM_NAME,
			TypeHash = imgui.cImHashStr(build.PROGRAM_NAME),
		}

		imgui.AddSettingsHandler(&handler)
		if os2.exists(string(io.IniFilename)) {
			imgui.LoadIniSettingsFromDisk(io.IniFilename)
		}
		else {
			load_layout_from_memory(&client.layouts, DEFAULT_LAYOUT_INI, false)
		}
	}

	client.wake_proc = wake_proc

	// Create paths
	client.paths.theme_folder = filepath.join({data_dir, "Themes"}, context.allocator)
	client.paths.persistent_state = filepath.join({data_dir, "settings.json"}, context.allocator)
	client.paths.layout_folder = filepath.join({data_dir, "Layouts"}, context.allocator)
	client.paths.settings = filepath.join({config_dir, "settings.ini"}, context.allocator)

	themes_init(client)
	theme_set_defaults(&global_theme)
	layouts_init(&client.layouts, data_dir)

	// Analysis
	analysis_init(&client.analysis)

	// Set defaults
	client.enable_media_controls = true

	load_settings(&client.settings, client.paths.settings)
	apply_settings(client)

	return true
}

destroy :: proc(client: ^Client) {
	save_settings(&client.settings, client.paths.settings)
	delete(client.paths.layout_folder)
	delete(client.paths.persistent_state)
	delete(client.paths.theme_folder)
	sys.async_dialog_destroy(&client.dialogs.remove_missing_files)
	themes_destroy(client)
	layouts_destroy(&client.layouts)
	analysis_destroy(&client.analysis)
}

handle_events :: proc(client: ^Client, sv: ^Server) {
	update_layout(&client.layouts, &client.window_archetypes)

	if client.media_controls.enabled {
		track_info: media_controls.Track_Info

		if client.media_controls.display_track != sv.current_track_id {
			track_id := sv.current_track_id
			client.media_controls.display_track = track_id

			if track, track_found := server.library_find_track(sv.library, track_id); track_found {
				md := track.properties
				path_buf: [512]u8
				es := string(cstring(""))

				track_info.album = strings.unsafe_string_to_cstring(md[.Album].(string) or_else "")
				track_info.artist = strings.unsafe_string_to_cstring(md[.Artist].(string) or_else "")
				track_info.title = strings.unsafe_string_to_cstring(md[.Title].(string) or_else "")
				track_info.genre = strings.unsafe_string_to_cstring(md[.Genre].(string) or_else "")
				track_info.path = server.library_find_track_path_cstring(sv.library, path_buf[:], track.id) or_else nil

				media_controls.set_track_info(&track_info)
			}
		}

		playback_state: media_controls.State
		if sv.current_track_id == 0 {playback_state = .Stopped}
		else if server.is_paused(sv^) {playback_state = .Paused}
		else {playback_state = .Playing}

		if client.media_controls.display_state != playback_state {
			log.debug("Set media controls state to", playback_state)
			client.media_controls.display_state = playback_state
			media_controls.set_state(playback_state)
		}
	}

	if client.want_apply_settings {
		client.want_apply_settings = false
		apply_settings(client)
	}
	
	if client.settings != client.saved_settings {
		client.saved_settings = client.settings
		log.debug("Saving settings...")
		save_settings(&client.settings, client.paths.settings)
	}
}

frame :: proc(cl: ^Client, sv: ^Server, prev_frame_start, frame_start: time.Tick) -> (delta: f32) {
	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor()

	delta = cast(f32) time.duration_seconds(time.tick_diff(prev_frame_start, frame_start))
	delta = min(delta, 5)

	cl.uptime += f64(delta)
	cl.frame_count += 1
	cl.tick_last_frame = prev_frame_start
	cl.delta = delta

	// Media controls
	if cl.enable_media_controls && !cl.media_controls.enabled {
		cl.media_controls.enabled = true
		log.debug("Enabling media controls...")
		media_controls.enable(_media_controls_handler, sv)
	}
	else if !cl.enable_media_controls && cl.media_controls.enabled {
		cl.media_controls.enabled = false
		log.debug("Disabling media controls...")
		media_controls.disable()
	}

	if current_metadata, ok := add_window_instance(cl, WINDOW_METADATA, 0); ok {
		state := cast(^Metadata_Window) current_metadata
		state.track_id = sv.current_track_id
	}
	else {log.error("Failed to update metadata window")}

	sys.async_file_dialog_get_results(&cl.dialogs.add_folders, &sv.scan_queue)
	server.library_update_categories(&sv.library)
	update_analysis(cl, sv, delta)

	if result, have_result := sys.async_dialog_get_result(&cl.dialogs.remove_missing_files); have_result && result {
		server.library_remove_missing_tracks(&sv.library)
	}
	
	// Set new background if one was selected from the dialog
	{
		background_path: [dynamic]Path
		
		if sys.async_file_dialog_get_results(&cl.dialogs.set_background, &background_path) {
			if len(background_path) >= 1 {
				set_background(cl, string(cstring(&background_path[0][0])))
			}
			delete(background_path)
		}
	}

	_draw_background(cl^)
	_main_menu_bar(cl, sv)
	_status_bar(cl, sv)

	show_all_windows(cl, sv)

	if cl.show_window_manager {
		if cl.bring_window_manager_to_front {
			cl.bring_window_manager_to_front = false
			imgui.SetNextWindowFocus()
		}
		if imgui.Begin("Window Manager", &cl.show_window_manager) {
			show_window_manager_window(cl)
		}
		imgui.End()
	}
	
	// Settings
	if cl.show_settings_window {
		if cl.bring_settings_window_to_front {
			imgui.SetNextWindowFocus()
			cl.bring_settings_window_to_front = false
		}
		if imgui.Begin("Settings", &cl.show_settings_window) {
			show_settings_editor(cl)
		}
		imgui.End()
	}

	if cl.windows.licenses.show {
		if imgui.Begin("Licenses", &cl.windows.licenses.show) {
			show_license_window()
		}
		imgui.End()
	}

	if cl.windows.about.show {
		if imgui.Begin("About", &cl.windows.about.show) {
			show_about_window()
		}
		imgui.End()
	}

	// Debug
	when ODIN_DEBUG {
		if cl.show_imgui_theme_editor {
			imgui.ShowStyleEditor()
		}
	}

	return
}

set_background :: proc(client: ^Client, path: string) -> (ok: bool) {
	width, height: i32

	sys.video_destroy_texture(client.background.texture)
	client.background.texture = 0
	
	file_data, file_error := os2.read_entire_file_from_path(path, context.allocator)
	if file_error != nil {log.error(file_error); return}
	defer delete(file_data)
	
	image_data := stbi.load_from_memory(raw_data(file_data), auto_cast len(file_data), &width, &height, nil, 4)
	if image_data == nil {return}
	defer stbi.image_free(image_data)
	
	client.background.texture = sys.video_create_texture(image_data, int(width), int(height)) or_return
	client.background.width = int(width)
	client.background.height = int(height)

	for &c in client.settings.background {c = 0}
	copy(client.settings.background[:len(client.settings.background)-1], path)

	ok = true
	return
}

enable_media_controls :: proc(client: ^Client, sv: ^Server) {
	client.enable_media_controls = true
	media_controls.enable(_media_controls_handler, sv)
}

disable_media_controls :: proc(client: ^Client) {
	media_controls.disable()
}

_media_controls_handler :: proc "c" (data: rawptr, signal: media_controls.Signal) {
	sv := cast(^Server) data
	context = sv.ctx

	log.debug(signal)

	switch signal {
		case .Next: server.play_next_track(sv)
		case .Prev: server.play_prev_track(sv)
		case .Pause: server.set_paused(sv, true)
		case .Play: server.set_paused(sv, false)
		case .Stop:
	}
}

@private
_go_to_artist :: proc(cl: ^Client, md: Track_Properties) -> bool {
	state := cast(^Track_Category_Window) (bring_window_to_front(cl, WINDOW_ARTIST) or_return)
	track_category_window_set_view_by_name(state, md[.Artist].(string) or_else "")
	return true
}

@private
_go_to_album :: proc(cl: ^Client, md: Track_Properties) -> bool {
	state := cast(^Track_Category_Window) (bring_window_to_front(cl, WINDOW_ALBUMS) or_return)
	track_category_window_set_view_by_name(state, md[.Album].(string) or_else "")
	return true
}

@private
_go_to_genre :: proc(cl: ^Client, md: Track_Properties) -> bool {
	state := cast(^Track_Category_Window) (bring_window_to_front(cl, WINDOW_GENRES) or_return)
	track_category_window_set_view_by_name(state, md[.Genre].(string) or_else "")
	return true
}

@private
_main_menu_bar :: proc(client: ^Client, sv: ^Server) {
	if !imgui.BeginMainMenuBar() {return}
	defer imgui.EndMainMenuBar()

	save_layout_popup_id := imgui.GetID("save_layout")
	show_save_layout_popup(&client.layouts, save_layout_popup_id)

	// Menus
	if imgui.BeginMenu("File") {
		if imgui.MenuItem("Add folders") {
			sys.open_async_file_dialog(&client.dialogs.add_folders, .Audio, {.SelectFolders, .SelectMultiple})
		}

		if imgui.MenuItem("Scan for new music") {
			paths := sv.library.path_allocator
			for dir in paths.dirs {
				path: Path
				util.copy_string_to_buf(path[:], path_pool.get_dir_path(dir))
				log.debug("Queue folder", cstring(&path[0]))
				server.queue_files_for_scanning(sv, {path})
			}
		}

		imgui.SetItemTooltip("Scan all folders added to your library for new music")
		imgui.Separator()

		if imgui.MenuItem("Remove all missing tracks") {
			sys.async_dialog_open(&client.dialogs.remove_missing_files, .OkCancel, "Confirm action", "Remove all missing tracks from library? This cannot be undone")
		}

		imgui.Separator()

		if imgui.MenuItem("Settings") {
			client.show_settings_window = true
			client.bring_settings_window_to_front = true
		}

		imgui.Separator()

		if imgui.MenuItem("Exit") {
			client.want_quit = true
		}
		imgui.EndMenu()
	}

	if imgui.BeginMenu("View") {
		window := show_window_selector(client)
		if window != nil do window.want_bring_to_front = true

		imgui.Separator()
		if imgui.MenuItem("Manage windows") {
			client.show_window_manager = true
			client.bring_window_manager_to_front = true
		}

		imgui.Separator()
		if imgui.MenuItem("Edit theme") {
			bring_window_to_front(client, WINDOW_THEME_EDITOR)
		}

		if imgui.MenuItem("Change background") {
			sys.open_async_file_dialog(&client.dialogs.set_background, .Image, {})
		}

		imgui.EndMenu()
	}

	if imgui.BeginMenu("Layout") {
		show_layout_menu_items(&client.layouts, save_layout_popup_id)
		imgui.EndMenu()
	}

	if imgui.BeginMenu("Help") {
		if imgui.MenuItem("Licenses") {
			client.windows.licenses.show = true
		}
		if imgui.MenuItem("About") {
			client.windows.about.show = true
		}
		imgui.EndMenu()
	}

	when ODIN_DEBUG {
		if imgui.BeginMenu("Debug") {
			imgui.MenuItemBoolPtr("ImGui theme editor", nil, &client.show_imgui_theme_editor)
			if imgui.MenuItem("Fake library update") {
				sv.library.serial += 1
			}
			imgui.EndMenu()
		}
	}
	
	// Volume
	imgui.Separator()
	{
		vol := server.get_volume(sv) * 100
		imgui.SetNextItemWidth(100)
		if imgui.SliderFloat("##volume", &vol, 0, 100, "%.0f%%") {
			server.set_volume(sv, vol / 100)
		}
	}

	// Peak meter
	imgui.Separator()
	client.analysis.need_update_peaks = true
	imx.peak_meter(
		"##peak_meter",
		client.analysis.peaks[:client.analysis.channels],
		global_theme.custom_colors[.PeakLoud],
		global_theme.custom_colors[.PeakQuiet],
		{100, 0}
	)
	
	// Playback controls
	imgui.Separator()

	switch sv.playback_mode {
		case .Playlist: {
			if imgui.MenuItem(ICON_ARROW) {
				server.set_playback_mode(sv, .RepeatPlaylist)
			}
			imgui.SetItemTooltip("Stop after playlist")
		}
		case .RepeatPlaylist: {
			if imgui.MenuItem(ICON_REPEAT) {
				server.set_playback_mode(sv, .RepeatSingle)
			}
			imgui.SetItemTooltip("Repeat playlist")
		}
		case .RepeatSingle: {
			if imgui.MenuItem(ICON_REPEAT_SINGLE) {
				server.set_playback_mode(sv, .Playlist)
			}
			imgui.SetItemTooltip("Repeat track")
		}
	}

	{
		value := sv.enable_shuffle
		if imgui.MenuItemBoolPtr(ICON_SHUFFLE, nil, &value) {
			server.set_shuffle_enabled(sv, value)
		}
		imgui.SetItemTooltip("Shuffle")
	}

	imgui.Separator()
	if imgui.MenuItem(ICON_STOP) {
		server.stop_playback(sv)
	}
	imgui.SetItemTooltip("Stop playback")

	if imgui.MenuItem(ICON_PREVIOUS) {
		server.play_prev_track(sv)
	}
	imgui.SetItemTooltip("Step back in queue")

	if imgui.MenuItem(server.is_paused(sv^) ? ICON_PLAY : ICON_PAUSE) {
		server.set_paused(sv, !server.is_paused(sv^))
	}
	imgui.SetItemTooltip("Play/pause")

	if imgui.MenuItem(ICON_NEXT) {
		server.play_next_track(sv)
	}
	imgui.SetItemTooltip("Step forward in queue")

	imgui.Separator()

	// Seek bar
	{
		second := server.get_track_second(sv)
		duration := server.get_track_duration_seconds(sv)

		lh, lm, ls := time.clock_from_seconds(auto_cast second)
		rh, rm, rs := time.clock_from_seconds(auto_cast duration)

		imx.textf(
			64,
			"%02d:%02d:%02d/%02d:%02d:%02d",
			lh, lm, ls,
			rh, rm, rs,
		)

		if imx.scrubber("##seek_bar", &second, 0, duration) {
			server.seek_to_second(sv, cast(int) second)
		}
	}
}

_status_bar :: proc(cl: ^Client, sv: ^Server) -> bool {
	if !imx.begin_status_bar() {return false}
	defer imx.end_status_bar()

	state := &cl.windows.status_bar
	info := sv.current_track_info

	if state.displayed_track_id != sv.current_track_id {
		state.displayed_track_id = sv.current_track_id
		if sv.current_track_id == 0 {return false}
		track := server.library_find_track(sv.library, state.displayed_track_id) or_return
		state.metadata = track.properties
		state.artist = {}
		state.album = {}
		state.title = {}
		util.copy_string_to_buf(state.artist[:], state.metadata[.Artist].(string) or_else "")
		util.copy_string_to_buf(state.album[:], state.metadata[.Album].(string) or_else "")
		util.copy_string_to_buf(state.title[:], state.metadata[.Title].(string) or_else "")
	}

	if state.displayed_track_id != 0 {
		button :: proc(buf: []u8) -> bool {
			if buf[0] == 0 {imgui.TextDisabled("?"); return false}
			imgui.PushIDPtr(raw_data(buf))
			defer imgui.PopID()

			return imgui.MenuItem(cstring(raw_data(buf)))
		}

		if button(state.album[:]) {_go_to_album(cl, state.metadata)}
		imgui.SetItemTooltip("Album")
		imgui.Separator()
		if button(state.artist[:]) {_go_to_artist(cl, state.metadata)}
		imgui.SetItemTooltip("Artist")
		imgui.Separator()
		if button(state.title[:]) {_go_to_album(cl, state.metadata)}
		imgui.SetItemTooltip("Track title")
		imgui.Separator()
		imx.text_unformatted(string(cstring(&info.format_name[0])))
		imgui.Separator()
		imx.text_unformatted(string(cstring(&info.codec[0])))
		imgui.Separator()
		imx.text(16, info.samplerate, "Hz")
		imgui.Separator()
		switch info.channels {
		case 1: imx.text_unformatted("Mono")
		case 2: imx.text_unformatted("Stereo")
		case: imx.text(24, info.channels, "channels")
		}
		imgui.Separator()
	}

	if progress, is_running := server.get_background_scan_progress(sv^); is_running {
		input_count := progress.input_file_count
		output_count := progress.files_scanned
		frac := f32(output_count) / f32(input_count)

		if !progress.counting_files {
			imx.text(64, "Scanning metadata (", output_count, "/", input_count, ")", sep = "")
		}
		else {
			imx.text_unformatted("Counting tracks...")
		}
		imgui.ProgressBar(frac, {200, 0})
		imgui.Separator()
	}

	return true
}

@private
_draw_background :: proc(client: Client) {
	display_size := imgui.GetIO().DisplaySize
	drawlist := imgui.GetBackgroundDrawList()

	w := f32(client.background.width)
	h := f32(client.background.height)
	ww := display_size.x
	wh := display_size.y
	
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
		client.background.texture,
		{0, 0},
		{w, h},
	)
}

@private
_imgui_settings_open_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, name: cstring
) -> rawptr {
	archetype_name: string
	instance_number: int

	cl := cast(^Client) handler.UserData
	context = cl.ctx

	fmt.println(name)
	name_parts := strings.split_n(string(name), "@", 2)
	defer delete(name_parts)

	if len(name_parts) == 0 {return nil}

	archetype_name = name_parts[0]

	if len(name_parts) >= 2 {
		instance_number = strconv.parse_int(name_parts[1]) or_else 0
	}

	return add_window_instance_from_name(cl, archetype_name, instance_number) or_else nil
}

@private
_imgui_settings_read_line_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line: cstring
) {
	cl := cast(^Client) handler.UserData
	context = cl.ctx

	if entry == nil || len(line) == 0 {return}

	window := cast(^Window_Base) entry
	line_parts := strings.split_n(string(line), "=", 2)
	defer delete(line_parts)
	if len(line_parts) < 2 {return}

	archetype, archetype_found := cl.window_archetypes[window.archetype]
	if !archetype_found {return}

	if line_parts[0] == "Open" {
		if parsed, parse_ok := strconv.parse_int(line_parts[1]); parse_ok {
			window.open = parsed >= 1
		}
	}
	else if archetype.configure != nil {
		archetype.configure(window, line_parts[0], line_parts[1])
	}
}

@private
_imgui_settings_write_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
) {
	cl := cast(^Client) handler.UserData
	context = cl.ctx

	for _, archetype in cl.window_archetypes {
		for instance, instance_number in archetype.instances {
			if instance == nil {continue}
			imgui.TextBuffer_appendf(out_buf, "[RAT MP][%s@%d]\n", archetype.internal_name, i32(instance_number))
			imgui.TextBuffer_appendf(out_buf, "Open=%d\n", i32(instance.open))
			if archetype.save_config != nil {
				archetype.save_config(instance, out_buf)
			}
		}
	}
}

@private
_set_track_drag_drop_payload :: proc(tracks: []Track_ID) {
	imgui.SetDragDropPayload("TRACKS", raw_data(tracks), auto_cast(size_of(Track_ID) * len(tracks)))
	imgui.SetTooltip("%d tracks", i32(len(tracks)))
}

@private
get_track_drag_drop_payload :: proc(allocator: runtime.Allocator) -> (tracks: []Track_ID, have_payload: bool) {
	payload := imgui.AcceptDragDropPayload("TRACKS")
	if payload == nil do return

	assert(payload.DataSize % size_of(Track_ID) == 0)
	length := payload.DataSize / size_of(Track_ID)

	tracks = slice.clone((cast([^]Track_ID) payload.Data)[:length], allocator)
	have_payload = true

	return
}
