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

Path :: [384]u8

Create_Texture_Proc :: #type proc(data: rawptr, width, height: int) -> (imgui.TextureID, bool)
Destroy_Texture_Proc :: #type proc(texture: imgui.TextureID)

/*Property :: union {
	int,
	string,
	f32,
}*/

Client :: struct {
	ctx: runtime.Context,

	want_quit: bool,
	create_texture_proc: Create_Texture_Proc,
	destroy_texture_proc: Destroy_Texture_Proc,

	selected_user_playlist_id: Playlist_ID,

	tick_last_frame: time.Tick,
	frame_count: int,
	selection: _Selection,
	folder_queue: [dynamic]Path,
	background_scan: _Background_Scan,
	library_sort_spec: server.Track_Sort_Spec,
	metadata_window: _Metadata_Window,
	waveform_window: _Waveform_Window,
	window_state: [_Window]_Window_State,
	background: struct {
		texture: imgui.TextureID,
		width, height: int,
		path: string,
	},
	show_imgui_theme_editor: bool,
	show_memory_usage: bool,
	
	dialogs: struct {
		set_background: _File_Dialog_State,
		remove_missing_files: _Dialog_State,
		add_folders: _File_Dialog_State,
	},
	
	theme: Theme,
	current_theme_name: cstring,
	theme_editor: _Theme_Editor_State,

	paths: struct {
		theme_folder: string,
		persistent_state: string,
		layout_folder: string,
	},

	theme_names: [dynamic]cstring,

	loaded_fonts: []Load_Font,

	analysis: _Analysis_State,

	user_playlist_window: _Playlist_List_Window,
	categories: struct {
		artists: _Playlist_List_Window,
		albums: _Playlist_List_Window,
		genres: _Playlist_List_Window,
		folders: _Playlist_List_Window,
	},

	enable_media_controls: bool,
	media_controls: struct {
		display_track: Track_ID,
		display_state: media_controls.State,
		enabled: bool,
	},

	layouts: _Layout_State,

	wake_proc: proc(),
}

init :: proc(
	client: ^Client, sv: ^Server,
	create_texture_proc: Create_Texture_Proc,
	destroy_texture_proc: Destroy_Texture_Proc,
	data_dir, config_dir: string,
	wake_proc: proc(),
) -> bool {
	client.ctx = context
	log.info("ImGui version:", imgui.GetVersion())

	io := imgui.GetIO()
	io.ConfigFlags |= {.DockingEnable}

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
			_load_layout_from_memory(client, DEFAULT_LAYOUT_INI, false)
		}
	}

	client.create_texture_proc = create_texture_proc
	client.destroy_texture_proc = destroy_texture_proc
	client.wake_proc = wake_proc

	// Create paths
	client.paths.theme_folder = filepath.join({data_dir, "Themes"}, context.allocator)
	client.paths.persistent_state = filepath.join({data_dir, "settings.json"}, context.allocator)
	client.paths.layout_folder = filepath.join({data_dir, "Layouts"}, context.allocator)

	_scan_theme_folder(client)
	theme_set_defaults(&client.theme)
	_scan_layouts_folder(client)

	// Analysis
	_init_analysis(client)

	// Set defaults
	client.enable_media_controls = true

	load_persistent_state(client)

	return true
}

destroy :: proc(client: ^Client) {
	save_persistent_state(client^)
	delete(client.selection.tracks)
	delete(client.current_theme_name)
	delete(client.background.path)
	_background_scan_wait_for_results(nil, &client.background_scan)
	_async_dialog_destroy(&client.dialogs.remove_missing_files)
}

handle_events :: proc(client: ^Client, sv: ^Server) {
	_update_layout(client)

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
}

frame :: proc(client: ^Client, sv: ^Server, prev_frame_start, frame_start: time.Tick) {
	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor()

	/*if client.frame_count == 0 {
		delta = 1.0/60.0
	}
	else {
		delta = cast(f32) time.duration_seconds(time.tick_since(client.tick_last_frame))
	}*/

	delta := cast(f32) time.duration_seconds(time.tick_diff(prev_frame_start, frame_start))

	client.frame_count += 1
	client.tick_last_frame = prev_frame_start

	// Media controls
	if client.enable_media_controls && !client.media_controls.enabled {
		client.media_controls.enabled = true
		log.debug("Enabling media controls...")
		media_controls.enable(_media_controls_handler, sv)
	}
	else if !client.enable_media_controls && client.media_controls.enabled {
		client.media_controls.enabled = false
		log.debug("Disabling media controls...")
		media_controls.disable()
	}

	_async_file_dialog_get_results(&client.dialogs.add_folders, &client.folder_queue)
	_background_scan_output_results(&sv.library, &client.background_scan)
	_update_analysis(client, sv, delta)
	server.library_update_categories(&sv.library)

	if result, have_result := _async_dialog_get_result(&client.dialogs.remove_missing_files); have_result && result {
		server.library_remove_missing_tracks(&sv.library)
	}
	
	// Set new background if one was selected from the dialog
	{
		background_path: [dynamic]Path
		
		if _async_file_dialog_get_results(&client.dialogs.set_background, &background_path) {
			if len(background_path) >= 1 {
				set_background(client, string(cstring(&background_path[0][0])))
			}
			delete(background_path)
		}
	}

	_draw_background(client^)
	_main_menu_bar(client, sv)

	// Begin scanning folders if needed
	if len(client.folder_queue) > 0 && !_background_scan_is_running(client.background_scan) {
		_begin_background_scan(&client.background_scan, client.folder_queue[:])
		clear(&client.folder_queue)
	}
	else if _background_scan_is_running(client.background_scan) {
		scan := client.background_scan
		if imgui.Begin("Metadata Scan Progress") {
			input_count := scan.file_count
			output_count := len(scan.output.metadata)
			progress := f32(output_count) / f32(input_count)

			if scan.files_counted {
				imgui.Text("Scanning metadata (%u/%u)", u32(output_count), u32(input_count))
			}
			else {
				imgui.Text("Calculating...")
			}
			imgui.ProgressBar(progress, {imgui.GetContentRegionAvail().x, 0})
		}

		imgui.End()
	}

	// Library
	if _begin_window(client, .Library) {
		context_menu: _Track_Context_Menu_Result
		defer _process_track_context_menu_results(client, sv, context_menu)

		if table, show_table := _begin_track_table(
			"Library", {}, sv.current_track_id,
			sv.library.track_ids[:], &client.selection
		); show_table {
			if _track_table_update_sort_spec(&client.library_sort_spec) {
				server.sort_library_tracks(sv.library, client.library_sort_spec)
			}

			for _track_table_row(sv.library, &table, client.theme) {
				if _play_track_input_pressed() {
					server.play_playlist(sv, sv.library.track_ids[:], {}, table.track_id)
				}

				if imgui.BeginPopupContextItem() {
					_show_generic_track_context_menu_items(client, sv, table.track_id, table.metadata, &context_menu)
					imgui.EndPopup()
				}
			}

			_end_track_table(table)
		}

		imgui.End()
	}

	// Queue
	if _begin_window(client, .Queue) {
		want_remove_selection := false
		context_menu: _Track_Context_Menu_Result
		defer _process_track_context_menu_results(client, sv, context_menu)

		if table, show_table := _begin_track_table(
			"Queue", {}, sv.current_track_id,
			sv.queue[:], &client.selection
		); show_table {
			for _track_table_row(sv.library, &table, client.theme) {
				if _play_track_input_pressed() {
					server.set_queue_position(sv, table.track_index)
				}

				if imgui.BeginPopupContextItem() {
					_show_generic_track_context_menu_items(client, sv, table.track_id, table.metadata, &context_menu)
					want_remove_selection |= imgui.MenuItem("Remove")
					imgui.EndPopup()
				}
			}

			_end_track_table(table)
		}

		imgui.End()

		if want_remove_selection {
			for track_id in client.selection.tracks[:] {
				track_index := slice.linear_search(sv.queue[:], track_id) or_continue
				ordered_remove(&sv.queue, track_index)
			}

			_selection_clear(&client.selection)
		}
	}

	// Playlists
	if _begin_window(client, .Playlists) {
		_show_playlist_list_window(client, sv, &client.user_playlist_window, &sv.library.user_playlists, allow_edit=true)
		imgui.End()
	}

	// Folders
	if _begin_window(client, .Folders) {
		_show_playlist_list_window(client, sv, &client.categories.folders, &sv.library.categories.folders)
		imgui.End()
	}

	// Artists
	if _begin_window(client, .Artists) {
		_show_playlist_list_window(client, sv, &client.categories.artists, &sv.library.categories.artists)
		imgui.End()
	}

	// Albums
	if _begin_window(client, .Albums) {
		_show_playlist_list_window(client, sv, &client.categories.albums, &sv.library.categories.albums)
		imgui.End()
	}

	// Genres
	if _begin_window(client, .Genres) {
		_show_playlist_list_window(client, sv, &client.categories.genres, &sv.library.categories.genres)
		imgui.End()
	}

	// Metadata
	if _begin_window(client, .Metadata) {
		_show_metadata_details(client, sv, sv.current_track_id, &client.metadata_window)
		imgui.End()
	}

	// Waveform
	if _begin_window(client, .WaveformSeek) {
		_show_waveform_window(sv, &client.waveform_window)
		imgui.End()
	}

	// Spectrum
	if _begin_window(client, .Spectrum) {
		_show_spectrum_window(client, &client.analysis)
		imgui.End()
	}

	// Oscilloscope
	if _begin_window(client, .Oscilloscope) {
		_show_oscilloscope_window(client)
		imgui.End()
	}

	// Theme editor
	if _begin_window(client, .ThemeEditor) {
		_show_theme_editor(client, &client.theme, &client.theme_editor)
		imgui.End()
	}

	// Debug
	when ODIN_DEBUG {
		if client.show_imgui_theme_editor {
			imgui.ShowStyleEditor()
		}

		if client.show_memory_usage {
			_show_memory_usage(client, sv^)
		}
	}
}

set_background :: proc(client: ^Client, path: string) -> (ok: bool) {
	width, height: i32
	delete(client.background.path)

	client.destroy_texture_proc(client.background.texture)
	client.background.texture = nil

	file_data, file_error := os2.read_entire_file_from_path(path, context.allocator)
	if file_error != nil {log.error(file_error); return}
	defer delete(file_data)

	image_data := stbi.load_from_memory(raw_data(file_data), auto_cast len(file_data), &width, &height, nil, 4)
	if image_data == nil {return}
	defer stbi.image_free(image_data)

	client.background.texture = client.create_texture_proc(image_data, int(width), int(height)) or_return
	client.background.width = int(width)
	client.background.height = int(height)
	client.background.path = strings.clone(path)

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
	client.categories.artists.selected_id = {serial=auto_cast Metadata_Component.Artist, pool=id}
	_bring_window_to_front(client, .Artists)
}

@private
_go_to_album :: proc(client: ^Client, md: Track_Metadata) {
	id := server.library_hash_string(md.values[.Album].(string) or_else "")
	client.categories.albums.selected_id = {serial=auto_cast Metadata_Component.Album, pool=id}
	_bring_window_to_front(client, .Albums)
}

@private
_go_to_genre :: proc(client: ^Client, md: Track_Metadata) {
	id := server.library_hash_string(md.values[.Genre].(string) or_else "")
	client.categories.genres.selected_id = {serial=auto_cast Metadata_Component.Genre, pool=id}
	_bring_window_to_front(client, .Genres)
}

@private
_main_menu_bar :: proc(client: ^Client, sv: ^Server) {
	STOP_ICON :: ""
	SHUFFLE_ICON :: ""
	PREV_TRACK_ICON :: ""
	NEXT_TRACK_ICON :: ""
	PLAY_ICON :: ""
	PAUSE_ICON :: ""
	REPEAT_ICON :: ""

	if !imgui.BeginMainMenuBar() {return}
	defer imgui.EndMainMenuBar()

	save_layout_popup_id := imgui.GetID("save_layout")
	_show_save_layout_popup(client, save_layout_popup_id)

	// Menus
	if imgui.BeginMenu("File") {
		if imgui.MenuItem("Add folders") {
			_open_async_file_dialog(&client.dialogs.add_folders)
		}

		if imgui.MenuItem("Scan for new music") {
			paths := sv.library.path_allocator
			for dir in paths.dirs {
				path: Path
				util.copy_string_to_buf(path[:], path_pool.get_dir_path(dir))
				log.debug("Queue folder", cstring(&path[0]))
				append(&client.folder_queue, path)
			}
		}

		imgui.SetItemTooltip("Scan all folders added to your library for new music")
		imgui.Separator()

		if imgui.MenuItem("Remove all missing tracks") {
			_async_dialog_open(&client.dialogs.remove_missing_files, .OkCancel, "Confirm action", "Remove all missing tracks from library? This cannot be undone")
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
			_open_async_file_dialog(&client.dialogs.set_background, select_folders=false, multiselect=false, file_type=.Image)
		}

		imgui.EndMenu()
	}

	if imgui.BeginMenu("Layout") {
		_show_layout_menu_items(client, save_layout_popup_id)
		imgui.EndMenu()
	}

	when ODIN_DEBUG {
		if imgui.BeginMenu("Debug") {
			imgui.MenuItemBoolPtr("ImGui theme editor", nil, &client.show_imgui_theme_editor)
			if imgui.MenuItem("Memory usage") {
				client.show_memory_usage = true
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
	_show_peak_meter_widget("##peak_meter", client.analysis.peaks[:client.analysis.channels], client.theme, {100, 0})
	
	// Playback controls
	imgui.Separator()
	if imgui.MenuItem(sv.enable_shuffle ? SHUFFLE_ICON : REPEAT_ICON) {
		server.set_shuffle_enabled(sv, !sv.enable_shuffle)
	}

	if imgui.MenuItem(PREV_TRACK_ICON) {
		server.play_prev_track(sv)
	}

	if imgui.MenuItem(server.is_paused(sv^) ? PLAY_ICON : PAUSE_ICON) {
		server.set_paused(sv, !server.is_paused(sv^))
	}

	if imgui.MenuItem(NEXT_TRACK_ICON) {
		server.play_next_track(sv)
	}

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

		if _show_scrubber_widget("##seek_bar", &second, 0, duration) {
			server.seek_to_second(sv, cast(int) second)
		}
	}
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
