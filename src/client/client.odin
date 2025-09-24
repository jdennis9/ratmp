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

	want_quit: bool,

	selected_user_playlist_id: Playlist_ID,

	tick_last_frame: time.Tick,
	frame_count: int,
	library_sort_spec: server.Track_Sort_Spec,
	metadata_window: _Metadata_Window,
	waveform_window: _Waveform_Window,
	window_state: [_Window]_Window_State,
	background: struct {
		texture: imgui.TextureID,
		width, height: int,
	},
	show_imgui_theme_editor: bool,
	show_memory_usage: bool,
	
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
	
	analysis: _Analysis_State,
	
	windows: struct {
		theme_editor: _Theme_Editor_State,
		user_playlists: _Playlist_List_Window,
		categories: struct {
			artists: _Playlist_List_Window,
			albums: _Playlist_List_Window,
			genres: _Playlist_List_Window,
			folders: _Playlist_List_Window,
		},
		settings: Settings_Editor,
		library: struct {
			table: _Track_Table_2,
			filter: [128]u8,
		},
		queue: struct {
			table: _Track_Table_2,
		},
		folders: _Folders_Window,
		metadata_editor: _Metadata_Editor,
		status_bar: struct {
			displayed_track_id: Track_ID,
			metadata: Track_Metadata,
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

	layouts: _Layout_State,

	track_drag_drop_payload: []Track_ID,

	settings: Settings,
	saved_settings: Settings,
	show_settings_window: bool,
	bring_settings_window_to_front: bool,
	want_apply_settings: bool,

	wake_proc: proc(),
}

init :: proc(
	client: ^Client, sv: ^Server,
	data_dir, config_dir: string,
	wake_proc: proc(),
) -> bool {
	client.ctx = context
	log.info("ImGui version:", imgui.GetVersion())

	io := imgui.GetIO()

	for info, window in _WINDOW_INFO {
		client.window_state[window].show = .AlwaysShow in info.flags
	}

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
			_load_layout_from_memory(&client.layouts, DEFAULT_LAYOUT_INI, false)
		}
	}

	client.wake_proc = wake_proc

	// Create paths
	client.paths.theme_folder = filepath.join({data_dir, "Themes"}, context.allocator)
	client.paths.persistent_state = filepath.join({data_dir, "settings.json"}, context.allocator)
	client.paths.layout_folder = filepath.join({data_dir, "Layouts"}, context.allocator)
	client.paths.settings = filepath.join({config_dir, "settings.ini"}, context.allocator)

	_themes_init(client)
	theme_set_defaults(&global_theme)
	_layouts_init(&client.layouts, data_dir)

	// Analysis
	_analysis_init(&client.analysis)

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
	_themes_destroy(client)
	_layouts_destroy(&client.layouts)
	_analysis_destroy(&client.analysis)
}

handle_events :: proc(client: ^Client, sv: ^Server) {
	_update_layout(&client.layouts, &client.window_state)

	if client.media_controls.enabled {
		if client.media_controls.display_track != sv.current_track_id {
			track_id := sv.current_track_id
			client.media_controls.display_track = track_id

			if md, track_found := server.library_get_track_metadata(sv.library, track_id); track_found {
				media_controls.set_metadata(
					strings.unsafe_string_to_cstring(md.values[.Artist].(string) or_else string(cstring(""))),
					strings.unsafe_string_to_cstring(md.values[.Album].(string) or_else string(cstring(""))),
					strings.unsafe_string_to_cstring(md.values[.Title].(string) or_else string(cstring(""))),
				)
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

	cl.frame_count += 1
	cl.tick_last_frame = prev_frame_start

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

	sys.async_file_dialog_get_results(&cl.dialogs.add_folders, &sv.scan_queue)
	server.library_update_categories(&sv.library)
	_update_analysis(cl, sv, delta)

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

	if ODIN_DEBUG {
		imgui.ShowDemoWindow()
	}

	// Library
	if _begin_window(cl, .Library) {
		state := &cl.windows.library
		filter_cstring := cstring(&state.filter[0])
		context_id := imgui.GetID("##library_track_context")

		imgui.InputTextWithHint("##library_filter", "Filter", filter_cstring, auto_cast len(state.filter))

		_track_table_update(&state.table, sv.library.serial, sv.library, sv.library.track_ids[:], {}, string(filter_cstring))
		table_result := _track_table_show(state.table, "##library_table", context_id, sv.current_track_id)

		if table_result.sort_spec != nil {server.library_sort(&sv.library, table_result.sort_spec.?)}
		_track_table_process_results(state.table, table_result, cl, sv, {})

		context_result := _track_table_show_context(state.table, table_result, context_id, {.NoRemove}, sv^)
		_track_table_process_context(state.table, table_result, context_result, cl, sv)

		imgui.End()
	} else {_free_track_table(&cl.windows.library.table)}

	// Queue
	if _begin_window(cl, .Queue) {
		state := &cl.windows.queue
		context_id := imgui.GetID("##track_context")

		_track_table_update(&state.table, sv.queue_serial, sv.library, sv.queue[:], {serial=max(u32)}, "", {.NoSort})
		table_result := _track_table_show(state.table, "##queue", context_id, sv.current_track_id)

		//if table_result.sort_spec != nil {server.sort_queue(sv, table_result.sort_spec.?)}
		_track_table_process_results(state.table, table_result, cl, sv, {.SetQueuePos})

		if payload, have_payload := _track_table_accept_drag_drop(table_result, context.allocator); have_payload {
			server.append_to_queue(sv, payload, {})
			delete(payload)
		}
		
		context_result := _track_table_show_context(state.table, table_result, context_id, {}, sv^)
		_track_table_process_context(state.table, table_result, context_result, cl, sv)

		if context_result.remove {
			selection := _track_table_get_selection(state.table)
			defer delete(selection)
			server.remove_tracks_from_queue(sv, selection)
		}
		
		imgui.End()
	} else {_free_track_table(&cl.windows.queue.table)}

	// Playlists
	if _begin_window(cl, .Playlists) {
		_show_playlist_list_window(cl, sv, &cl.windows.user_playlists, &sv.library.user_playlists, allow_edit=true)
		imgui.End()
	}
	else {_free_track_table(&cl.windows.user_playlists.track_table)}

	// Folders
	if _begin_window(cl, .Folders) {
		//_show_playlist_list_window(cl, sv, &cl.windows.categories.folders, &sv.library.categories.folders)
		_folders_window_show(cl, sv)
		imgui.End()
	}
	else {_free_track_table(&cl.windows.categories.folders.track_table)}

	// Artists
	if _begin_window(cl, .Artists) {
		_show_playlist_list_window(cl, sv, &cl.windows.categories.artists, &sv.library.categories.artists)
		imgui.End()
	}
	else {_free_track_table(&cl.windows.categories.artists.track_table)}

	// Albums
	if _begin_window(cl, .Albums) {
		_show_playlist_list_window(cl, sv, &cl.windows.categories.albums, &sv.library.categories.albums)
		imgui.End()
	}
	else {_free_track_table(&cl.windows.categories.albums.track_table)}

	// Genres
	if _begin_window(cl, .Genres) {
		_show_playlist_list_window(cl, sv, &cl.windows.categories.genres, &sv.library.categories.genres)
		imgui.End()
	}
	else {_free_track_table(&cl.windows.categories.genres.track_table)}

	// Metadata
	if _begin_window(cl, .Metadata) {
		_show_metadata_details(cl, sv, sv.current_track_id, &cl.metadata_window)
		imgui.End()
	}

	// Waveform
	if _begin_window(cl, .WaveformSeek) {
		_show_waveform_window(sv, &cl.waveform_window)
		imgui.End()
	}

	// Spectrum
	if _begin_window(cl, .Spectrum) {
		_show_spectrum_window(cl, &cl.analysis)
		imgui.End()
	}

	// Oscilloscope
	if _begin_window(cl, .Oscilloscope) {
		_show_oscilloscope_window(cl)
		imgui.End()
	}

	// Theme editor
	if _begin_window(cl, .ThemeEditor) {
		_show_theme_editor(cl, &cl.windows.theme_editor)
		imgui.End()
	}

	if _begin_window(cl, .MetadataEditor) {
		_show_metadata_editor(&cl.windows.metadata_editor, &sv.library)
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
			_show_license_window()
		}
		imgui.End()
	}

	if cl.windows.about.show {
		if imgui.Begin("About", &cl.windows.about.show) {
			_show_about_window()
		}
		imgui.End()
	}

	// Debug
	when ODIN_DEBUG {
		if cl.show_imgui_theme_editor {
			imgui.ShowStyleEditor()
		}

		if cl.show_memory_usage {
			_show_memory_usage(cl, sv^)
		}
	}

	return
}

set_background :: proc(client: ^Client, path: string) -> (ok: bool) {
	width, height: i32

	sys.imgui_destroy_texture(client.background.texture)
	client.background.texture = 0
	
	file_data, file_error := os2.read_entire_file_from_path(path, context.allocator)
	if file_error != nil {log.error(file_error); return}
	defer delete(file_data)
	
	image_data := stbi.load_from_memory(raw_data(file_data), auto_cast len(file_data), &width, &height, nil, 4)
	if image_data == nil {return}
	defer stbi.image_free(image_data)
	
	client.background.texture = sys.imgui_create_texture(image_data, int(width), int(height)) or_return
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
_go_to_artist :: proc(client: ^Client, md: Track_Metadata) {
	id := server.library_hash_string(md.values[.Artist].(string) or_else "")
	client.windows.categories.artists.viewing_id = {serial=auto_cast Metadata_Component.Artist, pool=id}
	_bring_window_to_front(client, .Artists)
}

@private
_go_to_album :: proc(client: ^Client, md: Track_Metadata) {
	id := server.library_hash_string(md.values[.Album].(string) or_else "")
	client.windows.categories.albums.viewing_id = {serial=auto_cast Metadata_Component.Album, pool=id}
	_bring_window_to_front(client, .Albums)
}

@private
_go_to_genre :: proc(client: ^Client, md: Track_Metadata) {
	id := server.library_hash_string(md.values[.Genre].(string) or_else "")
	client.windows.categories.genres.viewing_id = {serial=auto_cast Metadata_Component.Genre, pool=id}
	_bring_window_to_front(client, .Genres)
}

@private
_main_menu_bar :: proc(client: ^Client, sv: ^Server) {
	STOP_ICON :: ""
	ARROW_ICON :: ""
	SHUFFLE_ICON :: ""
	PREV_TRACK_ICON :: ""
	NEXT_TRACK_ICON :: ""
	PLAY_ICON :: ""
	PAUSE_ICON :: ""
	REPEAT_ICON :: ""
	REPEAT_SINGLE_ICON :: ""

	if !imgui.BeginMainMenuBar() {return}
	defer imgui.EndMainMenuBar()

	save_layout_popup_id := imgui.GetID("save_layout")
	_show_save_layout_popup(&client.layouts, save_layout_popup_id)

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
		if imgui.MenuItem("Folders") {_bring_window_to_front(client, .Folders)}
		if imgui.MenuItem("Artists") {_bring_window_to_front(client, .Artists)}
		if imgui.MenuItem("Albums") {_bring_window_to_front(client, .Albums)}
		if imgui.MenuItem("Genres") {_bring_window_to_front(client, .Genres)}

		imgui.SeparatorText("Visualizers")
		if imgui.MenuItem("Wave bar") {_bring_window_to_front(client, .WaveformSeek)}
		if imgui.MenuItem("Spectrum") {_bring_window_to_front(client, .Spectrum)}
		if imgui.MenuItem("Oscilloscope") {_bring_window_to_front(client, .Oscilloscope)}

		imgui.Separator()
		if imgui.MenuItem("Edit theme") {
			_bring_window_to_front(client, .ThemeEditor)
		}

		if imgui.MenuItem("Change background") {
			sys.open_async_file_dialog(&client.dialogs.set_background, .Image, {})
		}

		imgui.EndMenu()
	}

	if imgui.BeginMenu("Layout") {
		_show_layout_menu_items(&client.layouts, save_layout_popup_id)
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
			if imgui.MenuItem("Memory usage") {
				client.show_memory_usage = true
			}
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
			if imgui.MenuItem(ARROW_ICON) {
				server.set_playback_mode(sv, .RepeatPlaylist)
			}
			imgui.SetItemTooltip("Stop after playlist")
		}
		case .RepeatPlaylist: {
			if imgui.MenuItem(REPEAT_ICON) {
				server.set_playback_mode(sv, .RepeatSingle)
			}
			imgui.SetItemTooltip("Repeat playlist")
		}
		case .RepeatSingle: {
			if imgui.MenuItem(REPEAT_SINGLE_ICON) {
				server.set_playback_mode(sv, .Playlist)
			}
			imgui.SetItemTooltip("Repeat track")
		}
	}

	{
		value := sv.enable_shuffle
		if imgui.MenuItemBoolPtr(SHUFFLE_ICON, nil, &value) {
			server.set_shuffle_enabled(sv, value)
		}
		imgui.SetItemTooltip("Shuffle")
	}

	imgui.Separator()
	if imgui.MenuItem(STOP_ICON) {
		server.stop_playback(sv)
	}
	imgui.SetItemTooltip("Stop playback")

	if imgui.MenuItem(PREV_TRACK_ICON) {
		server.play_prev_track(sv)
	}
	imgui.SetItemTooltip("Step back in queue")

	if imgui.MenuItem(server.is_paused(sv^) ? PLAY_ICON : PAUSE_ICON) {
		server.set_paused(sv, !server.is_paused(sv^))
	}
	imgui.SetItemTooltip("Play/pause")

	if imgui.MenuItem(NEXT_TRACK_ICON) {
		server.play_next_track(sv)
	}
	imgui.SetItemTooltip("Step forward in queue")

	imgui.Separator()

	// Seek bar
	{
		second := cast(f32) server.get_track_second(sv)
		duration := cast(f32) server.get_track_duration_seconds(sv)

		lh, lm, ls := time.clock_from_seconds(auto_cast second)
		rh, rm, rs := time.clock_from_seconds(auto_cast duration)

		imgui.Text(
			"%02d:%02d:%02d/%02d:%02d:%02d",
			i32(lh), i32(lm), i32(ls),
			i32(rh), i32(rm), i32(rs),
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
		state.metadata = server.library_get_track_metadata(sv.library, state.displayed_track_id) or_return
		state.artist = {}
		state.album = {}
		state.title = {}
		util.copy_string_to_buf(state.artist[:], state.metadata.values[.Artist].(string) or_else "")
		util.copy_string_to_buf(state.album[:], state.metadata.values[.Album].(string) or_else "")
		util.copy_string_to_buf(state.title[:], state.metadata.values[.Title].(string) or_else "")
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
			imgui.Text("Scanning metadata (%u/%u)", u32(output_count), u32(input_count))
		}
		else {
			imgui.Text("Counting tracks...")
		}
		imgui.ProgressBar(frac, {200, 0})
		imgui.Separator()
	}

	return true
}

@private
_begin_window :: proc(client: ^Client, window: _Window) -> bool {
	name_buf: [128]u8
	info := _WINDOW_INFO[window]
	state := &client.window_state[window]

	if !state.show && .AlwaysShow not_in info.flags {return false}

	fmt.bprint(name_buf[:], info.display_name, "###", info.internal_name, sep="")

	if state.bring_to_front {
		state.bring_to_front = false
		imgui.SetNextWindowFocus()
	}

	if .AlwaysShow in info.flags {
		if !imgui.Begin(cstring(&name_buf[0]), nil, state.flags | info.imgui_flags) {
			imgui.End()
			return false
		}
	}
	else {
		if !imgui.Begin(cstring(&name_buf[0]), &state.show, state.flags | info.imgui_flags) {
			imgui.End()
			return false
		}
	}

	return true
}

@private
_bring_window_to_front :: proc(client: ^Client, window: _Window) {
	client.window_state[window].show = true
	client.window_state[window].bring_to_front = true
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

_show_memory_usage :: proc(client: ^Client, sv: Server) {
	show := imgui.Begin("Memory Usage", &client.show_memory_usage)
	if !show {
		imgui.End()
		return
	}
	
	defer imgui.End()

	library_usage: int
	library_usage += size_of(Track_ID) * len(sv.library.track_ids)
	library_usage += size_of(Track_Metadata) * len(sv.library.track_metadata)
	library_usage += 8 * len(sv.library.track_paths)
	
	imgui.Text("Library: %u KB", u32(library_usage) >> 10)
	
}

@private
_imgui_settings_open_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, name: cstring
) -> rawptr {
	client := cast(^Client) handler.UserData
	context = client.ctx
	name_str := string(name)
	fmt.println(name)
	for window, i in _WINDOW_INFO {
		if string(window.internal_name) == name_str {
			return cast(rawptr) (cast(uintptr) i + 1)
		}
	}

	return nil
}

@private
_imgui_settings_read_line_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line: cstring
) {
	client := cast(^Client) handler.UserData
	context = client.ctx
	if entry == nil || len(line) == 0 {return}

	window: _Window = cast(_Window) (uintptr(entry) - 1)
	if window < min(_Window) || window > max(_Window) {return}
	if .DontSaveState in _WINDOW_INFO[window].flags {return}

	line_parts := strings.split(string(line), "=")
	if len(line_parts) < 2 {return}
	defer delete(line_parts)

	parsed, parse_ok := strconv.parse_int(line_parts[1])
	if !parse_ok {client.window_state[window].show = true}
	else {client.window_state[window].show = parsed >= 1}
}

@private
_imgui_settings_write_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
) {
	client := cast(^Client) handler.UserData
	context = client.ctx

	for window, window_id in _WINDOW_INFO {
		if .DontSaveState in window.flags {continue}
		imgui.TextBuffer_appendf(out_buf, "[RAT MP][%s]\n", window.internal_name)
		imgui.TextBuffer_appendf(out_buf, "Open=%u\n", cast(u32)client.window_state[window_id].show)
	}
}

@private
_set_track_drag_drop_payload :: proc(tracks: []Track_ID) {
	log.debug("Set payload")
	imgui.SetDragDropPayload("TRACKS", raw_data(tracks), auto_cast(size_of(Track_ID) * len(tracks)), .Once)
	imgui.SetTooltip("%d tracks", i32(len(tracks)))
}

@private
_get_track_drag_drop_payload :: proc(allocator: runtime.Allocator) -> (tracks: []Track_ID, have_payload: bool) {
	payload := imgui.AcceptDragDropPayload("TRACKS")
	if payload == nil {return}

	assert(payload.DataSize % size_of(Track_ID) == 0)
	length := payload.DataSize / size_of(Track_ID)

	tracks = slice.clone((cast([^]Track_ID) payload.Data)[:length])
	have_payload = true

	return
}
