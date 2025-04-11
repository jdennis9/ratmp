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
package ui;

import "base:intrinsics";
import "base:runtime";
import "core:log";
import "core:strings";
import "core:thread";
import "core:slice";
import "core:math";
import "core:os";
import "core:fmt";
import "core:strconv";
import "core:time";

import imgui "../../libs/odin-imgui";

import "../signal";
import "../util";
import lib "../library";
import "../playback";
import "../video";
import "../prefs";
import "../theme";
import "../drag_drop";
import "../analysis";
import "../build";

ICON_FONT := #load("FontAwesome.otf");

STOP_ICON :: "";
SHUFFLE_ICON :: "";
PREV_TRACK_ICON :: "";
NEXT_TRACK_ICON :: "";
PLAY_ICON :: "";
PAUSE_ICON :: "";

PLAYING_COLOR :: 0xff3a93ff;

Window :: enum {
	Library,
	Navigation,
	Artists,
	Albums,
	Folders,
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
};

Window_Category :: enum {
	Music,
	Info,
	Editing,
	Visualizers,
};

WINDOW_FIRST_VISUALIZER :: Window.PeakMeter;

Window_Info :: struct {
	name: cstring,
	internal_name: cstring,
	category: Window_Category,
	show_proc: proc(),
	show: bool,
	flags: imgui.WindowFlags,
	bring_to_front: bool,
};

window_info := [Window]Window_Info {
	.Library = {
		name = "Library", internal_name = "library",
		category = .Music,
		show_proc = _show_library_window,
	},
	.Navigation = {
		name = "Navigation", internal_name = "navigation",
		category = .Music,
		show_proc = _show_navigation_window,
	},
	.Artists = {
		name = "Artists", internal_name = "artists",
		category = .Music,
		show_proc = _show_artists_window,
	},
	.Albums = {
		name = "Albums", internal_name = "albums",
		category = .Music,
		show_proc = _show_albums_window,
	},
	.Folders = {
		name = "Folders", internal_name = "folders",
		category = .Music,
		show_proc = _show_folders_window,
	},
	.Queue = {
		name = "Queue", internal_name = "queue",
		category = .Info,
		show_proc = _show_queue_window,
	},
	.Playlist = {
		name = "Playlist", internal_name = "playlist",
		category = .Music,
		show_proc = _show_selected_playlist_window,
	},
	.PlaylistTabs = {
		name = "Playlists (Tabs)", internal_name = "playlist_tabs",
		category = .Music,
		show_proc = _show_playlist_tabs_window,
	},
	.Metadata = {
		name = "Metadata", internal_name = "metadata",
		category = .Info,
		show_proc = _show_metadata_window,
	},
	.ThemeEditor = {
		name = "Edit Theme", internal_name = "theme_editor",
		category = .Editing,
		show_proc = _show_theme_editor_window,
	},
	.ReplaceMetadata = {
		name = "Replace Metadata", internal_name = "replace_metadata",
		category = .Editing,
		show_proc = _show_metadata_replacement_window,
	},
	.EditMetadata = {
		name = "Edit Metadata", internal_name = "edit_metadata",
		category = .Editing,
		show_proc = _show_metadata_editor,
	},
	.PeakMeter = {
		name = "Peak Meter", internal_name = "peak_meter",
		category = .Visualizers,
		show_proc = _show_peak_window,
	},
	.Spectrum = {
		name = "Spectrum", internal_name = "spectrum",
		category = .Visualizers,
		show_proc = _show_spectrum_window,
	},
	.WavePreview = {
		name = "Wave Preview", internal_name = "wave_preview",
		category = .Visualizers,
		show_proc = _show_wave_preview_window,
	},
};

window_category_info := [Window_Category]struct {
	name: cstring,	
} {
	.Editing = {"Editing"},
	.Info = {"Info"},
	.Music = {"Music"},
	.Visualizers = {"Visualizers"},
};

DEFAULT_LAYOUT_INI := #load("default_layout.ini", cstring);

@private
Playlist_Group_Window :: struct {
	selected_group_id: Maybe(u32),
};

@private
Offset_Length :: struct {
	offset, length: int,
};

@private
this: struct {
	ctx: runtime.Context,

	deferred_files: struct {
		pool: [dynamic]u8,
		files: [dynamic]Offset_Length,
		files_loaded: int,
		scanning: bool,
	},

	metadata: struct {
		thumbnail: video.Texture,
		comment: cstring,
	},

	selection: [dynamic]lib.Track,
	selected_playlist: lib.Playlist_ID,

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

	enable_imgui_theme_editor: bool,
	enable_imgui_demo_window: bool,

	platform_drag_drop_payload: [dynamic]string,
	want_to_drop_platform_drag_drop_payload: bool,

	want_reset_layout: bool,

	//metadata_save_job: ^lib.Metadata_Save_Job,
};

init :: proc() -> bool {
	this.ctx = context;
	io := imgui.GetIO();
	io.ConfigFlags |= {.DockingEnable, .NavEnableKeyboard};
	
	// Add settings handler
	handler := imgui.SettingsHandler {
		TypeName = build.PROGRAM_NAME,
		TypeHash = imgui.cImHashStr(build.PROGRAM_NAME),
		ReadOpenFn = _imgui_settings_handler_open_proc,
		ReadLineFn = _imgui_settings_handler_read_line_proc,
		WriteAllFn = _imgui_settings_handler_write_proc,
	};

	imgui.AddSettingsHandler(&handler);
	//imgui.SaveIniSettingsToDisk(io.IniFilename);
	imgui.LoadIniSettingsFromDisk(io.IniFilename);

	// Load settings if needed
	if !os.exists(cast(string) io.IniFilename) {
		log.debug("Loading default layout");
		imgui.LoadIniSettingsFromMemory(DEFAULT_LAYOUT_INI);
	}

	log.debug("ImGui version: ", imgui.VERSION);

	signal.install_handler(signal_handler);

	// Set window flags
	window_info[.Metadata].flags |= {.AlwaysVerticalScrollbar};

	// Set up system drag-drop
	drag_drop.set_interface(
		&{
			begin = _ext_drag_drop_begin,
			add_file = _ext_drag_drop_add_file,
			cancel = _ext_drag_drop_cancel,
			drop = _ext_drag_drop_drop,
			mouse_over = _ext_drag_drop_mouse_over,
		}
	);


	return true;
}

shutdown :: proc() {
	if this.deferred_files.pool != nil {
		delete(this.deferred_files.pool);
	}

	video.impl.destroy_texture(this.background);
	video.impl.destroy_texture(this.metadata.thumbnail);
	if this.metadata.comment != nil {delete(this.metadata.comment)}
}

@private
_load_fonts :: proc() {
	@static loaded_font: [512]u8;
	@static loaded_font_size: int;
	@static loaded_icon_size: int;

	io := imgui.GetIO();

	font_path := cstring(raw_data(prefs.prefs.strings[.Font][:]));
	log.debug("Font path:", font_path);
	when ODIN_OS == .Windows {
		if font_path == "" || !os.exists(string(font_path)) {
			font_path = "C:\\Windows\\Fonts\\calibrib.ttf";
		}
	}
	font_size := prefs.prefs.numbers[.FontSize];
	icon_size := prefs.prefs.numbers[.IconSize];

	if cstring(&loaded_font[0]) == font_path && loaded_font_size == font_size && loaded_icon_size == icon_size {
		return;
	}

	video.impl.invalidate_imgui_objects();
	defer video.impl.create_imgui_objects();

	fonts := io.Fonts;
	cfg := imgui.FontConfig {
		FontDataOwnedByAtlas = false,
		OversampleH = 2,
		OversampleV = 2,
		GlyphMaxAdvanceX = max(f32),
		RasterizerMultiply = 1,
		RasterizerDensity = 1,
		EllipsisChar = max(imgui.Wchar),
		MergeMode = true,
	};

	imgui.FontAtlas_Clear(fonts);

	if font_path != "" && os.exists(string(font_path)) {
		if imgui.FontAtlas_AddFontFromFileTTF(fonts, font_path, auto_cast font_size) == nil {
			imgui.FontAtlas_AddFontDefault(fonts);
		}
	}
	else {
		imgui.FontAtlas_AddFontDefault(fonts);
	}

	icon_ranges := []imgui.Wchar {
		0xf048, 0xf052, // Playback controls
		0xf026, 0xf028, // Volume
		0xf074, 0xf074, // Shuffle
		0
	};

	imgui.FontAtlas_AddFontFromMemoryTTF(fonts, raw_data(ICON_FONT), 
		cast(i32) len(ICON_FONT), auto_cast icon_size, &cfg, raw_data(icon_ranges));

	util.copy_cstring(loaded_font[:], font_path);
	loaded_font_size = font_size;
	loaded_icon_size = icon_size;
}

@private
_apply_prefs :: proc() {
	log.debug("Applying preferences...");
	io := imgui.GetIO();
	
	// Load background
	{
		@static loaded_background: [512]u8;
		path := prefs.get_string(.Background);

		if string(cstring(&loaded_background[0])) != path {
			video.impl.destroy_texture(this.background);
			if path != "" {
				this.background, this.background_width, this.background_height, _ = 
					video.load_texture(path);
			}
			else {
				this.background = {};
			}
			util.copy_string_to_buf(loaded_background[:], path);
		}
	}

	_load_fonts();

	// Load default theme
	theme.load(prefs.get_string(.Theme));
}

@private
signal_handler :: proc(sig: signal.Signal) {
	if sig == .ApplyPrefs {
		_apply_prefs();
	}
}

bring_window_to_front :: proc(win: Window) {
	window_info[win].bring_to_front = true;
}

@private
_add_files_iterator :: proc(path: string, is_folder: bool, data: rawptr) {
	if is_folder {
		util.for_each_file_in_folder(path, _add_files_iterator, data);
	}
	else {
		offset := len(this.deferred_files.pool);
		_, err := append_string(&this.deferred_files.pool, path);
		if err != .None {return;}
		append(&this.deferred_files.files, Offset_Length{offset = offset, length = len(path)});
	}
}

@private
_async_scan_thread_proc :: proc(_: ^thread.Thread) {
	context.logger = log.create_console_logger();
	df := &this.deferred_files;
	for f in df.files {
		file := transmute(string) df.pool[f.offset:][:f.length];
		lib.add_file(file);
		//intrinsics.atomic_exchange(&df.files_loaded, intrinsics.atomic_add(&df.files_loaded, 1));
		df.files_loaded += 1;
	}

	delete(df.files);
	df.files = nil;
	delete(df.pool);
	df.pool = nil;
	intrinsics.atomic_store(&df.scanning, false);
	intrinsics.atomic_store(&df.files_loaded, 0);

	log.debug("Async file scan done");
}

@private
_begin_async_scan :: proc() {
	log.debug("Begin async file scan");
	this.deferred_files.scanning = true;
	tp := thread.create(_async_scan_thread_proc);
	thread.start(tp);
}

/*@private
_begin_metadata_save_job :: proc() {
	if util.message_box(
		"Save Metadata Changes", .OkCancel,
		"Save all metadata changes to your music files? This cannot be undone."
	) {
		this.metadata_save_job = lib.save_metadata_changes_async();
	}
}*/

show :: proc() {
	@static tick_last_frame: time.Tick;
	@static is_first_frame := true;
	delta: f32;

	if is_first_frame {
		delta = 1.0/60.0;
		is_first_frame = false;
	}
	else {
		delta = cast(f32) time.duration_seconds(time.tick_since(tick_last_frame));
	}
	tick_last_frame = time.tick_now();

	// Layouts need to be loaded before NewFrame or else docking settings
	// aren't respected
	if this.want_reset_layout {
		imgui.LoadIniSettingsFromMemory(DEFAULT_LAYOUT_INI);
		this.want_reset_layout = false;
	}

	io := imgui.GetIO();
	style := imgui.GetStyle();

	new_playlist_popup_name := cstring("New Playlist");
	this.new_playlist_popup_id = imgui.GetID(new_playlist_popup_name);

	imgui.PushStyleColor(.DockingEmptyBg, 0);
	imgui.DockSpaceOverViewport({}, nil, {});
	imgui.PopStyleColor();

	analysis.update(delta, 1.0/30.0);

	// Draw background
	if this.background.id != nil {
		drawlist := imgui.GetBackgroundDrawList();
		w := f32(this.background_width);
		h := f32(this.background_height);
		ww := io.DisplaySize.x;
		wh := io.DisplaySize.y;

		if h != wh {
			ratio := wh / h;
			w = math.ceil(w * ratio);
			h = math.ceil(h * ratio);
		}

		if w < ww {
			ratio := ww / w;
			w = math.ceil(w * ratio);
			h = math.ceil(h * ratio);
		}

		imgui.DrawList_AddImage(
			drawlist,
			this.background.id,
			{0, 0},
			{w, h},
		);
	}

	// Check if there are any files queued for processing and begin processing them if
	// needed
	if intrinsics.atomic_load(&this.deferred_files.files_loaded) < len(this.deferred_files.files) {
		df := &this.deferred_files;

		if !intrinsics.atomic_load(&df.scanning) {
			// There are tracks ready but they aren't being scanned
			_begin_async_scan();
		}

		// Show the scan progress
		size := imgui.Vec2{400, 100};
		center := imgui.Vec2{io.DisplaySize.x / 2.0, io.DisplaySize.y / 2.0};
		pos := imgui.Vec2{center.x - (size.x / 2.0), center.y - (size.y / 2.0)};

		imgui.SetNextWindowPos(pos);
		imgui.SetNextWindowSize(size);
		if imgui.Begin("Metadata Scan Progress", nil, imgui.WindowFlags_NoDecoration) {
			total_files := len(df.files);
			files_loaded := intrinsics.atomic_load(&df.files_loaded);
			progress := cast(f32) files_loaded / cast(f32) total_files;
			imgui.Text("Processing files (%d/%d)", cast(i32) files_loaded, cast(i32) total_files);
			imgui.ProgressBar(progress, {imgui.GetContentRegionAvail().x, 0});
		}
		imgui.End();
		return;
	}

	/*if this.metadata_save_job != nil {
		job := this.metadata_save_job;

		if !job.done {
			size := imgui.Vec2{400, 100};
			center := imgui.Vec2{io.DisplaySize.x / 2.0, io.DisplaySize.y / 2.0};
			pos := imgui.Vec2{center.x - (size.x / 2.0), center.y - (size.y / 2.0)};
	
			imgui.SetNextWindowPos(pos);
			imgui.SetNextWindowSize(size);
			if imgui.Begin("Metadata Save Progress", nil, imgui.WindowFlags_NoDecoration) {
				progress := cast(f32)job.tracks_completed / cast(f32)job.total_tracks;
				imgui.Text("Saving files (%d/%d)", cast(i32) job.tracks_completed, cast(i32) job.total_tracks);
				imgui.ProgressBar(progress, {imgui.GetContentRegionAvail().x, 0});
			}
			imgui.End();
			return;
		}
		else {
			this.metadata_save_job = nil;
		}
	}*/

	// -------------------------------------------------------------------------
	// Drag-drop
	// -------------------------------------------------------------------------
	if this.want_to_drop_platform_drag_drop_payload {
		for file in this.platform_drag_drop_payload {
			_add_files_iterator(file, os.is_dir(file), nil);
		}
	
		_ext_drag_drop_clear_payload();
		this.want_to_drop_platform_drag_drop_payload = false;
	}

	// -----------------------------------------------------------------------------
	// Hotkeys
	// -----------------------------------------------------------------------------
	if imgui.IsKeyPressed(.F1) {
		this.show_help = !this.show_help;
	}

	if imgui.IsKeyChordPressed(cast(i32) (imgui.Key.R | imgui.Key.ImGuiMod_Shift | imgui.Key.ImGuiMod_Ctrl)) {
		prefs.load();
		signal.post(.ApplyPrefs);
	}

	
	// -----------------------------------------------------------------------------
	// Preferences
	// -----------------------------------------------------------------------------

	if this.show_preferences {
		if imgui.Begin("Preferences", &this.show_preferences) {
			_show_preferences_window();
		}
		imgui.End();
	}

	// -------------------------------------------------------------------------
	// Main menu bar
	// -------------------------------------------------------------------------
	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Preferences") {
				this.show_preferences = true;
			}
			imgui.MenuItem("Minimize to tray");
			imgui.Separator();
			if imgui.MenuItem("Exit") {signal.post(.Exit);};
			imgui.EndMenu();
		}

		if imgui.BeginMenu("Library") {
			if imgui.MenuItem("Add files") {
				util.for_each_file_in_dialog(nil, _add_files_iterator, nil);
			}
			if imgui.MenuItem("Add folders") {
				util.for_each_file_in_dialog(nil, _add_files_iterator, nil, true);
			}
			/*imgui.Separator();
			if imgui.MenuItem("Save metadata changes") {
				_begin_metadata_save_job();
			}*/
			imgui.EndMenu();
		}

		if imgui.BeginMenu("View") {
			//if imgui.BeginMenu("Windows") {
				//for i in Window {
				//	imgui.MenuItemBoolPtr(window_info[i].name, nil, &this.show_window[i]);
				//}
				//imgui.EndMenu();
			//}
			for &window in window_info {
				if imgui.BeginMenu(window_category_info[window.category].name) {
					imgui.MenuItemBoolPtr(window.name, nil, &window.show);
					imgui.EndMenu();
				}
			}

			imgui.Separator();
			if imgui.MenuItem("Reset layout") {
				this.want_reset_layout = true;
			}
			imgui.EndMenu();
		}

		if imgui.BeginMenu("Help") {
			if imgui.MenuItem("Manual") {
				this.show_help = true;
			}
			if imgui.MenuItem("About") {
				this.show_about = true;
			}
			imgui.EndMenu();
		}

		when ODIN_DEBUG {
			if imgui.BeginMenu("Debug") {
				imgui.MenuItemBoolPtr("Show theme editor", nil, &this.enable_imgui_theme_editor);
				imgui.MenuItemBoolPtr("Show ImGui demo", nil, &this.enable_imgui_demo_window);
				imgui.EndMenu();
			}
		}

		// -----------------------------------------------------------------------------
		// Volume
		// -----------------------------------------------------------------------------
		{
			volume := playback.get_volume() * 100;
			imgui.SetNextItemWidth(100);
			if imgui.SliderFloat("##volume", &volume, 0, 100, "%.0f%%") {
				playback.set_volume(volume / 100);
			}
		}

		imgui.Separator();

		// -----------------------------------------------------------------------------
		// Playback controls
		// -----------------------------------------------------------------------------
		if imgui.MenuItem(STOP_ICON) {
			playback.stop();
		}

		if imgui.MenuItem(SHUFFLE_ICON, nil, playback.is_shuffle_enabled()) {
			playback.toggle_shuffle();
		}

		if imgui.MenuItem(PREV_TRACK_ICON) {
			playback.play_prev_track();
		}

		if playback.is_paused() {
			if imgui.MenuItem(PLAY_ICON) {
				playback.set_paused(false);
			}
		}
		else {
			if imgui.MenuItem(PAUSE_ICON) {
				playback.set_paused(true);
			}
		}

		if imgui.MenuItem(NEXT_TRACK_ICON) {
			playback.play_next_track();
		}
		imgui.Separator();
			
		// -----------------------------------------------------------------------------
		// Mini visualizer
		// -----------------------------------------------------------------------------
		{
			use_spectrum := prefs.get_property("ui_prefer_spectrum").(bool) or_else false;
			if use_spectrum {
				if _show_spectrum_widget("##spectrum", {100, imgui.GetFrameHeight()}) {
					prefs.set_property("ui_prefer_spectrum", false);
				}
			}
			else {
				if _show_peak_meter_widget("##peak_meter", {100, 0}) {
					prefs.set_property("ui_prefer_spectrum", true);
				}
			}
			imgui.Separator();
		}

		// ---------------------------------------------------------------------
		// Seek bar
		// ---------------------------------------------------------------------
		{
			@static seek_target: f32;
			pos := playback.get_second();
			duration := playback.get_duration();

			ch, cm, cs := util.split_seconds(cast(i32) pos);
			dh, dm, ds := util.split_seconds(cast(i32) duration);

			imgui.Text("%02d:%02d:%02d/%02d:%02d:%02d", ch, cm, cs, dh, dm, ds);
			
			frac := f32(pos) / f32(duration);
			if _show_scrubber_widget("##position", &frac, 0, 1) {
				seek_target = frac;
			}

			if imgui.IsItemDeactivated() {
				playback.seek(int(seek_target * f32(duration)));
			}
		}

		imgui.EndMainMenuBar();
	}

	// -------------------------------------------------------------------------
	// Help
	// -------------------------------------------------------------------------
	if this.show_help {
		if imgui.Begin("Manual", &this.show_help) {
			_show_help_window();
		}
		imgui.End();
	}

	if this.show_about {
		if imgui.Begin("About", &this.show_about) {
			_show_about_window();
		}
		imgui.End();
	}

	// -----------------------------------------------------------------------------
	// Show windows
	// -----------------------------------------------------------------------------
	for &window in window_info {
		if window.bring_to_front {
			window.bring_to_front = false;
			window.show = true;
			log.debug("Bring to front", window.name);
			imgui.SetNextWindowFocus();
		}

		if !window.show || window.show_proc == nil {continue}

		name_buf: [128]u8;
		fmt.bprint(name_buf[:127], window.name, "###", window.internal_name, sep="");

		if imgui.Begin(cstring(&name_buf[0]), &window.show, window.flags) {
			window.show_proc();
		}
		imgui.End();
	}

	// -------------------------------------------------------------------------
	// New playlist popup
	// -------------------------------------------------------------------------
	imgui.SetNextWindowSize({400, 150});
	if imgui.BeginPopupModal(new_playlist_popup_name, nil, {.NoResize}) {
		defer imgui.EndPopup();

		@static input: [128]u8;
		@static error: lib.Add_Playlist_Error;
		commit := false;

		commit |= imgui.InputText("Name your playlist", cstring(raw_data(input[:])), 128, {.EnterReturnsTrue});
		commit |= imgui.Button("Create");
		imgui.SameLine();
		if imgui.Button("Cancel") {imgui.CloseCurrentPopup()}

		if error != .None {
			error_str: cstring = error == .NameExists ? "Already a playlist with that name" : "Name is reserved";
			imgui.Text(error_str);
		}

		if commit {
			cstr := cstring(raw_data(input[:]));
			name := string(input[:len(cstr)]);
			_, error = lib.add_playlist(name);

			if error == .None {
				imgui.CloseCurrentPopup();
				error = .None;
				for &b in input {b = 0}
			}
		}
	}

	if this.enable_imgui_theme_editor {
		imgui.ShowStyleEditor();
	}

	if this.enable_imgui_demo_window {
		imgui.ShowDemoWindow(&this.enable_imgui_demo_window);
	}
}

@private
_show_library_window :: proc() {
	playlist := lib.get_default_playlist();
	action := _show_playlist_track_table(playlist^, {.NoRemove});
	_handle_base_track_table_action(action, playlist);
	_handle_playlist_playback_action(action, playlist^);
}

@private
_show_queue_window :: proc() {
	playlist := playback.get_queue();
	action := _show_playlist_track_table(playback.get_queue()^, {.NoAddToQueue, .NoFilter, .NoSort});
	_handle_base_track_table_action(action, playlist);
	_handle_queue_playback_action(action, playlist^);
}

@private
_show_selected_playlist_window :: proc() {
	playlist := lib.get_playlist(this.selected_playlist);
	if this.selected_playlist == 0 || playlist == nil {
		imgui.TextDisabled("No playlist selected");
		return;
	}

	action := _show_playlist_track_table(playlist^);
	_handle_base_track_table_action(action, playlist);
	_handle_playlist_playback_action(action, playlist^);
}

@private
_show_navigation_window :: proc() {
	playlists := lib.get_playlists();
	queued_playlist_id := playback.get_queued_playlist();
	delete_playlist_id: lib.Playlist_ID;

	table_flags := imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner;

	setup_columns :: proc() {		
		imgui.TableSetupColumn("Name", {.WidthStretch}, 0.8);
		imgui.TableSetupColumn("No. Tracks", {.WidthStretch}, 0.2);
	}

	if imgui.BeginTable("nav_table", 2, imgui.TableFlags_BordersInner) {
		defer imgui.EndTable();

		setup_columns();

		row :: proc(name: cstring, window: Window, length: int) {
			imgui.TableNextRow();
			if imgui.TableSetColumnIndex(0) {
				if imgui.Selectable(name, false, {.SpanAllColumns}) {
					bring_window_to_front(window);
				}
			}

			if imgui.TableSetColumnIndex(1) && length != 0 {
				imgui.TextDisabled("%d", cast(i32) length);
			}
		}
		
		row("Library", .Library, len(lib.get_default_playlist().tracks));
		row("Artists", .Artists, len(lib.get_artists()));
		row("Albums", .Albums, len(lib.get_albums()));
		row("Folders", .Folders, len(lib.get_folders()));
	}

	imgui.SeparatorText("Your Playlists");

	if imgui.Button("+ New playlist...") {
		imgui.OpenPopupID(this.new_playlist_popup_id);
	}

	if imgui.BeginTable("playlist_table", 2, table_flags|imgui.TableFlags_ScrollY) {
		defer imgui.EndTable();

		setup_columns();

		for &p, index in playlists {
			imgui.TableNextRow();

			if imgui.TableSetColumnIndex(0) {
				if imgui.Selectable(p.name, p.id == this.selected_playlist, {.SpanAllColumns}) {
					bring_window_to_front(.Playlist);
					this.selected_playlist = p.id;
				}

				if p.id == queued_playlist_id {
					imgui.TableSetBgColor(.RowBg0, PLAYING_COLOR);
				}
				
				if imgui.BeginPopupContextItem() {
					if imgui.MenuItem("Delete") {
						message_buf: [256]u8;
						message := fmt.bprint(message_buf[:], "Delete playlist ", p.name, "? This cannot be undone.", sep="");
						if util.message_box("Confirm delete", .OkCancel, message) {
							delete_playlist_id = p.id;
						}
					}
					imgui.EndPopup();
				}
			}

			if imgui.TableSetColumnIndex(1) {
				imgui.TextDisabled("%d", cast(i32) len(p.tracks));
			}
		}
	}

	if delete_playlist_id != 0 {
		lib.delete_playlist(delete_playlist_id);
	}
}

@private
_show_playlist_group_window :: proc(playlists: []lib.Playlist, state: ^Playlist_Group_Window) {
	
	if state.selected_group_id != nil {
		window_focused := imgui.IsWindowFocused();
		playlist: ^lib.Playlist;

		for &p in playlists {
			if p.group_id == state.selected_group_id.? {
				playlist = &p;
				break;
			}
		}

		if playlist == nil {
			state.selected_group_id = nil;
			return;
		}

		if imgui.Button("Go back") || (window_focused && imgui.IsKeyPressed(.Escape)) {
			state.selected_group_id = nil;
		}

		action := _show_playlist_track_table(playlist^, {.NoRemove, .NoFilter});
		_handle_base_track_table_action(action, playlist);
		_handle_playlist_playback_action(action, playlist^);
	}
	else {
		index_of_queued_playlist := -1;
		queued_group_id := playback.get_queued_group_id();
		for p, index in playlists {
			if p.group_id == queued_group_id {
				index_of_queued_playlist = index;
				break;
			}
		}

		action := show_playlist_list(playlists, index_of_queued_playlist);
		if action.select_playlist != nil {
			state.selected_group_id = playlists[action.select_playlist.?].group_id;
		}

		if action.play_playlist != nil {
			playlist := playlists[action.play_playlist.?];
			playback.play_playlist(playlist);
		}
	}
}

@private
_show_albums_window :: proc() {
	_show_playlist_group_window(lib.get_albums(), &this.albums_window);
}

@private
_show_artists_window :: proc() {
	_show_playlist_group_window(lib.get_artists(), &this.artists_window);
}

@private
_show_folders_window :: proc() {
	_show_playlist_group_window(lib.get_folders(), &this.folders_window);
}

@private
_show_playlist_tabs_window :: proc() {
	playlists := lib.get_playlists();

	if imgui.BeginTabBar("##playlists") {
		for &playlist in playlists {
			if imgui.BeginTabItem(playlist.name) {
				action := _show_playlist_track_table(playlist);
				_handle_base_track_table_action(action, &playlist);
				_handle_playlist_playback_action(action, playlist);
				imgui.EndTabItem();
			}
		}
	}
	imgui.EndTabBar();
}

@private
_show_metadata_window :: proc() {
	@static loaded_track: lib.Track;
	playing_track := playback.get_playing_track();

	if loaded_track != playing_track {
		loaded_track = playing_track;

		if this.metadata.thumbnail.id != nil {
			video.impl.destroy_texture(this.metadata.thumbnail);
			this.metadata.thumbnail = {};
		}

		if this.metadata.comment != nil {
			delete(this.metadata.comment);
			this.metadata.comment = nil;
		}

		if playing_track != 0 {
			this.metadata.thumbnail, _ = lib.load_track_thumbnail(playing_track);
			this.metadata.comment = lib.load_track_comment(playing_track);
		}
	}

	if playing_track == 0 {
		imgui.TextDisabled("No track playing");
		return;
	}

	avail_size := imgui.GetContentRegionAvail();
	if this.metadata.thumbnail.id != nil {
		imgui.PushStyleVarImVec2(.FramePadding, {0, 0});
		defer imgui.PopStyleVar();

		imgui.ImageButton("##thumbnail", this.metadata.thumbnail.id, {avail_size.x, avail_size.x});
		if imgui.BeginPopupContextItem() {
			_show_track_base_context_menu(0, playing_track);
			imgui.EndPopup();
		}
	}
	else {
		imgui.InvisibleButton("##thumbnail", {avail_size.x, avail_size.x});
		if imgui.BeginPopupContextItem() {
			_show_track_base_context_menu(0, playing_track);
			imgui.EndPopup();
		}
	}

	imgui.Separator();

	track := lib.get_track_info(playing_track);
	hours, minutes, seconds := util.split_seconds(cast(i32) track.duration_seconds);

	if imgui.BeginTable("Metadata Table", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("Type", {.WidthStretch}, 0.2);
		imgui.TableSetupColumn("Value", {.WidthStretch}, 0.8);

		row :: proc(name, value: cstring) {
			if len(value) > 0 {
				imgui.TableNextRow();
				imgui.TableSetColumnIndex(0);
				imgui.TextDisabled(name);
				imgui.TableSetColumnIndex(1);
				imgui.TextUnformatted(value);
			}
		}

		row_int :: proc(name: cstring, value: int) {
			if value != 0 {
				imgui.TableNextRow();
				imgui.TableSetColumnIndex(0);
				imgui.TextDisabled(name);
				imgui.TableSetColumnIndex(1);
				imgui.Text("%d", cast(i32) value);
			}
		}

		row("Title", track.title);
		row("Artist", track.artist);
		row("Album", track.album);
		row("Genre", track.genre);
		row_int("Track", track.track_number);
		row_int("Year", track.year);

		imgui.EndTable();
	}

	
	if this.metadata.comment != nil {
		imgui.Separator();
		imgui.TextWrapped(this.metadata.comment);
	}
}

@private
_show_metadata_replacement_window :: proc() {
	@static replace_with: [128]u8;
	@static to_replace: [128]u8;

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
	};

	imgui.InputText("Replace", cstring(&to_replace[0]), auto_cast len(to_replace));
	imgui.InputText("With", cstring(&replace_with[0]), auto_cast len(replace_with));

	imgui.Checkbox("Replace title", &state.replace_title);
	imgui.Checkbox("Replace artist", &state.replace_artist);
	imgui.Checkbox("Replace album", &state.replace_album);
	imgui.Checkbox("Replace genre", &state.replace_genre);
	imgui.Checkbox("In selection", &state.in_selection);

	if imgui.Button("Replace metadata") {
		mask: bit_set[lib.Metadata_Component];
		if state.replace_title {mask |= {.Title}}
		if state.replace_artist {mask |= {.Artist}}
		if state.replace_album {mask |= {.Album}}
		if state.replace_genre {mask |= {.Genre}}

		filter: []lib.Track = state.in_selection ? this.selection[:] : nil;		
		repl := lib.Metadata_Replacement {
			replace = string(cstring(&to_replace[0])),
			with = string(cstring(&replace_with[0])),
			replace_mask = {.Artist},
		};

		replaced_count := lib.perform_metadata_replacement(repl, filter);
		if replaced_count > 0 {
			message_buf: [1024]u8;
			message := fmt.bprint(
				message_buf[:], "Metadata was changed in", replaced_count, "tracks.",
				"These changes were not saved to the files,",
				"but can be seen in your library and will persist until the library file is deleted.",
				"To make the changes permanent, go Library -> Save metadata changes."
			);
			util.message_box("Metadata Replacement", .Message, message);
		}
		else {
			util.message_box("Metadata Replacements", .Message, "No metadata was replaced");
		}
	}
}

@private
_show_theme_editor_window :: proc() {
	current_theme := theme.get_current();
	style := imgui.GetStyle();
	@static unsaved_changes := false;
	@static name_buf: [128]u8;
	name_cstring := cstring(raw_data(name_buf[:]));
	
	imgui.InputText("Theme", name_cstring, len(name_buf));
	name_string := string(name_cstring);

	imgui.SameLine();
	if imgui.BeginCombo("##theme_picker", nil, {.NoPreview}) {
		list := theme.get_list();
		
		for name in list {
			if imgui.Selectable(name, current_theme == name) {
				theme.load(string(name));
				slice.fill(name_buf[:], 0);
				copy(name_buf[:127], string(name));
				unsaved_changes = false;
			}
		}
		
		imgui.EndCombo();
	}
	// Refresh themes when we open the theme selector menu
	if imgui.IsItemActivated() {
		theme.refresh_themes();
	}

	imgui.SameLine();
	if imgui.Button("Save") {
		if name_buf[0] == 0 {
			util.message_box("Name required", .Message, "Theme must have a name");
		}
		else if theme.exists(name_string) {
			message_buf: [256]u8;
			message := fmt.bprint(message_buf[:], "Overwrite theme ", name_cstring, "?", sep="");
			if util.message_box("Confirm overwrite", .OkCancel, message) {
				theme.save(string(name_cstring));
				unsaved_changes = false;
			}
		}
		else {
			theme.save(name_string);
			unsaved_changes = false;
		}
	}

	imgui.SameLine();
	if imgui.Button("Reload") {
		theme.load(name_string);
		unsaved_changes = false;
	}

	for col in imgui.Col {
		if col == .COUNT {continue}
		unsaved_changes |= imgui.ColorEdit4(imgui.GetStyleColorName(col), &style.Colors[col]);
	}

	if unsaved_changes {
		window_info[.ThemeEditor].flags |= {.UnsavedDocument};
	}
	else {
		window_info[.ThemeEditor].flags &= ~{.UnsavedDocument};
	}
}

@private
_show_preferences_window :: proc() {
	path_input_row :: proc(id: prefs.StringID, str_id: cstring, name: cstring) -> bool {
		buffer := prefs.prefs.strings[id][:];
		imgui.PushID(name);
		imgui.TableNextRow();
		imgui.TableSetColumnIndex(0);
		imgui.TextUnformatted(name);
		imgui.TableSetColumnIndex(1);
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x);
		commit := imgui.InputText(str_id, cstring(raw_data(buffer)), len(prefs.String_Buffer));
		imgui.TableSetColumnIndex(2);
		if imgui.Button("Browse") {
			_, file_picked := util.open_file_dialog(buffer);
			commit |= file_picked;
		}
		imgui.PopID();

		return commit;
	}

	number_input_row :: proc(id: prefs.NumberID, str_id: cstring, name: cstring) -> (commit: bool) {
		value := cast(i32) prefs.prefs.numbers[id];
		imgui.PushID(name);
		imgui.TableNextRow();
		imgui.TableSetColumnIndex(0);
		imgui.TextUnformatted(name);
		imgui.TableSetColumnIndex(1);
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x);
		commit |= imgui.DragInt(
			str_id, &value, 0.1,
			auto_cast prefs.NUMBER_INFO[id].min,
			auto_cast prefs.NUMBER_INFO[id].max
		);
		imgui.PopID();
		if commit {prefs.prefs.numbers[id] = cast(int) value}
		return;
	}

	string_choice_row :: proc(id: prefs.StringID, choices: []cstring, name: cstring) -> (commit: bool) {
		value := prefs.prefs.strings[id][:];
		imgui.PushID(name);
		imgui.TableNextRow();
		imgui.TableSetColumnIndex(0);
		imgui.TextUnformatted(name);
		imgui.TableSetColumnIndex(1);
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x);
		if imgui.BeginCombo("##combo", cstring(raw_data(value))) {
			for choice in choices {
				if imgui.MenuItem(choice) {
					util.copy_cstring(value, choice);
					commit = true;
				}
			}
			imgui.EndCombo();
		}
		imgui.PopID();
		return;
	}

	choice_row :: proc(id: prefs.ChoiceID, name: cstring) -> (commit: bool) {
		info := prefs.CHOICE_INFO[id];
		value := prefs.prefs.choices[id];
		current_choice_name: cstring;

		for choice in info.values {
			if choice.value == value {
				current_choice_name = choice.name;
				break;
			}
		}

		imgui.PushID(name);
		imgui.TableNextRow();
		imgui.TableSetColumnIndex(0);
		imgui.TextUnformatted(name);
		imgui.TableSetColumnIndex(1);
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x);
		if imgui.BeginCombo("##combo", current_choice_name) {
			for choice in info.values {
				if imgui.MenuItem(choice.name) {
					prefs.prefs.choices[id] = choice.value;
					commit = true;
				}
			}
			imgui.EndCombo();
		}
		imgui.PopID();

		return;
	}

	if imgui.BeginTable("Preferences Table", 3, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_RowBg) {
		changes := false;
		changes |= choice_row(.ClosePolicy, "Close Policy");
		changes |= path_input_row(.Background, "##background", "Background");
		changes |= path_input_row(.Font, "##font", "Font");
		changes |= number_input_row(.FontSize, "##font_size", "Font size");
		changes |= number_input_row(.IconSize, "##icon_size", "Icon size");
		changes |= string_choice_row(.Theme, theme.get_list(), "Theme");

		if changes {
			prefs.save();
			signal.post(.ApplyPrefs);
		}

		imgui.EndTable();
	}
}

@private
_show_help_window :: proc() {
	imgui.SeparatorText("Hotkeys");

	if imgui.BeginTable("Hotkey Table", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("Action");
		imgui.TableSetupColumn("Chord");

		row :: proc(action, chord: cstring) {
			imgui.TableNextRow();
			imgui.TableSetColumnIndex(0);
			imgui.TextUnformatted(action);
			imgui.TableSetColumnIndex(1);
			imgui.TextUnformatted(chord);
		}

		row("Toggle this window", "F1");
		row("Refresh preferences", "Ctrl + Shift + R");
		row("Select whole playlist", "Ctrl + A");
		row("Play selection", "Ctrl + Q");
		row("Jump to playing track", "Ctrl + Space");

		imgui.EndTable();
	}
}

// =============================================================================
// Selection
// =============================================================================

@private
_remove_selection_from_playlist :: proc(playlist: ^lib.Playlist) {
	for track in this.selection {
		index, found := slice.linear_search(playlist.tracks[:], track);
		if !found {continue}
		ordered_remove(&playlist.tracks, index);
	}

	lib.playlist_make_dirty(playlist);
}

@private
_add_selection_to_playlist :: proc(playlist: ^lib.Playlist) {
	lib.playlist_add_tracks(playlist, this.selection[:]);
}

@private
_is_track_selected :: proc(track: lib.Track) -> bool {
	return slice.contains(this.selection[:], track);
}

@private
_add_track_to_selection :: proc(track: lib.Track) {
	if (!_is_track_selected(track)) {
		append(&this.selection, track);
	}
}

@private
_clear_selection :: proc() {
	resize(&this.selection, 0);
}

@private
_extend_track_selection_to :: proc(playlist: lib.Playlist, track_index: int, deselect_others: bool) {
	for t, index in playlist.tracks {
		if index == track_index {continue;}

		if _is_track_selected(t) {
			if deselect_others {
				_clear_selection();
			}

			if index < track_index {
				for i in index..=track_index {
					_add_track_to_selection(playlist.tracks[i]);
				}
				return;
			}
			else {
				for i in track_index..=index {
					_add_track_to_selection(playlist.tracks[i]);
				}
				return;
			}
		}
	}

	if deselect_others {
		_clear_selection();
	}

	for i in 0..=track_index {
		_add_track_to_selection(playlist.tracks[i]);
	}
}

// Takes a slice of indices of tracks that passed the filter
@private
_extend_track_selection_with_filter_to :: proc(
	playlist: lib.Playlist, track_index_in_playlist: int, deselect_others: bool, filtered_tracks: []int,
) {
	index_of_track: int;

	for track_index, filter_index in filtered_tracks {
		if track_index == track_index_in_playlist {
			index_of_track = filter_index;
			break;
		}
	}

	for track_index, filter_index in filtered_tracks {
		if filter_index == index_of_track {continue}
		t := playlist.tracks[track_index];

		if _is_track_selected(t) {
			if deselect_others {
				_clear_selection();
			}

			if filter_index < index_of_track {
				for i in filter_index..=index_of_track {
					_add_track_to_selection(playlist.tracks[filtered_tracks[i]]);
				}
				return;
			}
			else {
				for i in index_of_track..=filter_index {
					_add_track_to_selection(playlist.tracks[filtered_tracks[i]]);
				}
				return;
			}
		}
	}

	if deselect_others {
		_clear_selection();
	}

	for i in 0..=index_of_track {
		_add_track_to_selection(playlist.tracks[filtered_tracks[i]]);
	}
}

@private
_select_whole_playlist :: proc(playlist: lib.Playlist) {
	resize(&this.selection, len(playlist.tracks));
	copy(this.selection[:], playlist.tracks[:]);
}

@private
_play_selection :: proc() {
	playback.play_track_array(this.selection[:]);
}

@private
_refresh_metadata_of_selected_tracks :: proc() {
	for t in this.selection {
		lib.refresh_track_metadata(t);
	}
}

@private
_add_selection_to_queue :: proc() {
	playback.append_to_queue(this.selection[:]);
}

@private
_get_selection_size :: proc() -> int {
	return len(this.selection);
}

// =============================================================================
// Action handling
// =============================================================================

@private
_get_selected_tracks_in_playlist :: proc(playlist: lib.Playlist) -> (tracks: [dynamic]lib.Track) {
	for track in playlist.tracks {
		if _is_track_selected(track) {
			append(&tracks, track);
		}
	}

	return tracks;
}

// Handles behaviour that is shared across all playlists
@private
_handle_base_track_table_action :: proc(action: Track_Table_Action, playlist: ^lib.Playlist) {
	ctrl_is_down := imgui.IsKeyDown(.ImGuiMod_Ctrl);
	altered := false;

	if action.select_all {
		_clear_selection();
		
		if playlist.filter_hash != 0 {
			for track_index in playlist.filter_tracks {
				append(&this.selection, playlist.tracks[track_index]);
			}
		}
		else {
			for track in playlist.tracks {
				append(&this.selection, track);
			}
		}
	}

	if action.select_track != nil {
		track_id := playlist.tracks[action.select_track.?];
		already_selected := _is_track_selected(track_id);

		if imgui.IsKeyDown(.ImGuiMod_Shift) {
			if playlist.filter_hash != 0 {
				_extend_track_selection_with_filter_to(playlist^, action.select_track.?, 
					!ctrl_is_down, playlist.filter_tracks[:]);
			}
			else {
				_extend_track_selection_to(playlist^, action.select_track.?, !ctrl_is_down);
			}
		}
		else {
			if !ctrl_is_down {_clear_selection()}
			append(&this.selection, playlist.tracks[action.select_track.?]);
		}
	}

	selected_tracks := _get_selected_tracks_in_playlist(playlist^);
	defer delete(selected_tracks);

	if action.add_to_queue {
		playback.append_to_queue(selected_tracks[:]);
	}

	if action.play_selection {
		playback.play_track_array(selected_tracks[:]);
	}
	
	if action.remove {
		_remove_selection_from_playlist(playlist);
		altered = true;
	}

	
	if action.add_selection_to_playlist {
		altered = true;
		_add_selection_to_playlist(playlist);
	}
	
	if action.drag_drop_payload != nil {
		altered = true;
		lib.playlist_add_tracks(playlist, action.drag_drop_payload);
		delete(action.drag_drop_payload);
	}
	
	if altered && playlist.id != 0 {
		lib.save_playlist(playlist.id);
	}
	
	if action.sort_spec != nil {
		spec := action.sort_spec.?;
		playlist.sort_metric = spec.metric;
		playlist.sort_order = spec.order;
		lib.sort_playlist(playlist);
	}

	lib.update_playlist_filter(playlist, action.filter, action.filter_hash);
}

@private
_handle_playlist_playback_action :: proc(action: Track_Table_Action, playlist: lib.Playlist) {
	ctrl_is_down := imgui.IsKeyDown(.ImGuiMod_Ctrl);
	if action.play_track != nil {
		track := playlist.tracks[action.play_track.?];
		if !_is_track_selected(track) {
			if !ctrl_is_down {_clear_selection()}
			append(&this.selection, track);
		}
		
		playback.play_playlist(playlist, track, true);
	}
}

@private
_handle_queue_playback_action :: proc(action: Track_Table_Action, playlist: lib.Playlist) {
	if action.play_track != nil {
		playback.play_track_at_position(action.play_track.?);
	}
}

// =============================================================================
// Drag-drop
// =============================================================================

@private
_ext_drag_drop_clear_payload :: proc() {
	for s in this.platform_drag_drop_payload {
		delete(s);
	}

	delete(this.platform_drag_drop_payload);
	this.platform_drag_drop_payload = nil;
}

@private
_ext_drag_drop_add_file :: proc "c" (path: cstring) {
	context = this.ctx;
	log.debug(path);
	append(&this.platform_drag_drop_payload, strings.clone_from_cstring(path));
}

@private
_ext_drag_drop_cancel :: proc "c" () {
	context = this.ctx;
	log.debug();

	_ext_drag_drop_clear_payload();
}

@private
_ext_drag_drop_drop :: proc "c" () {
	context = this.ctx;
	io := imgui.GetIO();
	log.debug();
	
	// Does this need to be done on Linux too?
	// Windows eats the mouse release event when you finish dragging
	/*when ODIN_OS == .Windows {
		imgui.IO_AddMouseButtonEvent(io, auto_cast imgui.MouseButton.Left, false);
	}*/

	this.want_to_drop_platform_drag_drop_payload = true;
}

@private
_ext_drag_drop_begin :: proc "c" () {
	context = this.ctx;
	io := imgui.GetIO();
	log.debug();
	
	// Need to tell ImGui that left mouse is down so drag-drop can work
	//imgui.IO_AddMouseButtonEvent(io, auto_cast imgui.MouseButton.Left, true);
}

@private
_ext_drag_drop_mouse_over :: proc "c" (x, y: f32) {
	context = this.ctx;
	io := imgui.GetIO();
	log.debug(x, y);

	//imgui.IO_AddMousePosEvent(io, x, y);
}

@private
_imgui_settings_handler_open_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, name: cstring
) -> rawptr {
	context = this.ctx;
	name_str := string(name);
	for window, i in window_info {
		if string(window.internal_name) == name_str {
			return cast(rawptr) (cast(uintptr) i + 1);
		}
	}

	return nil;
}

@private
_imgui_settings_handler_read_line_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line: cstring
) {
	context = this.ctx;
	if entry == nil {return}

	window: Window = cast(Window) (uintptr(entry) - 1);
	if window < min(Window) || window > max(Window) {return}

	line_parts := strings.split(string(line), "=");
	if len(line_parts) < 2 {return}

	parsed, parse_ok := strconv.parse_int(line_parts[1]);
	if !parse_ok {window_info[window].show = true}
	else {window_info[window].show = parsed >= 1}
}

@private
_imgui_settings_handler_write_proc :: proc "c" (
	ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
) {
	context = this.ctx;

	for window in window_info {
		imgui.TextBuffer_appendf(out_buf, "[RAT MP][%s]\n", window.internal_name);
		imgui.TextBuffer_appendf(out_buf, "Open=%u\n", cast(u32)window.show);
	}
}

// -----------------------------------------------------------------------------
// Metadata editor
// -----------------------------------------------------------------------------
@private
_show_metadata_editor :: proc() {
	if len(this.selection) == 0 {
		imgui.TextDisabled("No track selected");
		return;
	}
	
	table_flags := imgui.TableFlags_RowBg|imgui.TableFlags_SizingStretchProp|
	imgui.TableFlags_BordersInner;
	
	string_row :: proc(buf: cstring, buf_size: int, name: cstring, enable: ^bool = nil) {
		imgui.PushID(name);
		imgui.TableNextRow();
		imgui.TableSetColumnIndex(0);
		imgui.TextUnformatted(name);
		imgui.TableSetColumnIndex(1);
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x);
		imgui.InputText("##text", buf, auto_cast buf_size);
		if enable != nil && imgui.TableSetColumnIndex(2) {
			imgui.Checkbox("##enable", enable);
			imgui.SetItemTooltip("Apply");
		}
		imgui.PopID();
	}
	
	int_row :: proc(val: ^int, name: cstring, enable: ^bool = nil) {
		val_i32 := i32(val^);
		imgui.PushID(name);
		imgui.TableNextRow();
		imgui.TableSetColumnIndex(0);
		imgui.TextUnformatted(name);
		imgui.TableSetColumnIndex(1);
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x);
		if imgui.InputInt("##number", &val_i32) {
			val^ = int(val_i32);
		}
		if enable != nil && imgui.TableSetColumnIndex(2) {
			imgui.Checkbox("##enable", enable);
			imgui.SetItemTooltip("Apply");
		}
		imgui.PopID();
	}

	if len(this.selection) == 1 {
		path_buf: [384]u8;
		imgui.TextDisabled("Editing track %s", lib.get_track_path_cstring(this.selection[0], path_buf[:]));

		if imgui.BeginTable("##metadata_editor_table", 2, table_flags) {
			imgui.TableSetupColumn("Name", {}, 0.3);
			imgui.TableSetupColumn("Value", {}, 0.7);
	
			track := lib.get_track_info(this.selection[0]);

			string_row(track.title, lib.MAX_TRACK_TITLE_LENGTH+1, "Title");
			string_row(track.artist, lib.MAX_TRACK_ARTIST_LENGTH+1, "Artist");
			string_row(track.album, lib.MAX_TRACK_ALBUM_LENGTH+1, "Album");
			string_row(track.genre, lib.MAX_TRACK_GENRE_LENGTH+1, "Genre");
			int_row(&track.year, "Year");
			int_row(&track.track_number, "Track No.");
	
			imgui.EndTable();
		}

		/*if imgui.Button("Save to file") {
			if util.message_box("Save Metadata", .OkCancel, "Overwrite file metadata? This cannot be undone.") {
				lib.save_track_metadata(this.selection[0]);
			}
		}*/
	}
	else {
		imgui.TextDisabled("Editing %d tracks", i32(len(this.selection)));

		@static
		changes: struct {
			title: [lib.MAX_TRACK_TITLE_LENGTH+1]u8,
			artist: [lib.MAX_TRACK_ARTIST_LENGTH+1]u8,
			album: [lib.MAX_TRACK_ALBUM_LENGTH+1]u8,
			genre: [lib.MAX_TRACK_GENRE_LENGTH+1]u8,
			year: int,
			track: int,

			enable_title, enable_artist, enable_album, enable_genre, enable_year, enable_track: bool,
		};

		if imgui.BeginTable("##metadata_editor_table", 3, table_flags) {
			imgui.TableSetupColumn("Name", {}, 0.3);
			imgui.TableSetupColumn("Value", {}, 0.6);
			imgui.TableSetupColumn("Overwrite", {}, 0.1);

			string_row(cstring(&changes.title[0]), lib.MAX_TRACK_TITLE_LENGTH+1, "Title", &changes.enable_title);
			string_row(cstring(&changes.artist[0]), lib.MAX_TRACK_ARTIST_LENGTH+1, "Artist", &changes.enable_artist);
			string_row(cstring(&changes.album[0]), lib.MAX_TRACK_ALBUM_LENGTH+1, "Album", &changes.enable_album);
			string_row(cstring(&changes.genre[0]), lib.MAX_TRACK_GENRE_LENGTH+1, "Genre", &changes.enable_genre);
			int_row(&changes.year, "Year", &changes.enable_year);
			int_row(&changes.track, "Track No.", &changes.enable_track);
	
			imgui.EndTable();
		}

		if imgui.Button("Apply") {
			if util.message_box("Apply Changes?", .YesNo, "Apply these metadata changes to all selected tracks? This cannot be undone.") {
				for track_id in this.selection {
					track := lib.get_raw_track_info_pointer(track_id);
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
// Misc
// =============================================================================

@private
_show_about_window :: proc() {
	super_buf: [1024]u8;
	buf := super_buf[:1023];
	imgui.SeparatorText("Build Information");
	imgui.TextUnformatted(build.PROGRAM_NAME_AND_VERSION);
	imgui.Text("Odin version: %s", strings.unsafe_string_to_cstring(ODIN_VERSION));
	imgui.Text("OS: %s", cstring(ODIN_OS_STRING));
	imgui.Text("Optimization: %s", strings.unsafe_string_to_cstring(fmt.bprint(buf, ODIN_OPTIMIZATION_MODE)));

	imgui.SeparatorText("libsndfile");
    imgui.TextUnformatted("Copyright (C) 1999-2016 Erik de Castro Lopo <erikd@mega-nerd.com>\nAll rights reserved.");
    imgui.TextLinkOpenURL("https://libsndfile.github.io/libsndfile/");
    
    imgui.SeparatorText("libsamplerate");
    imgui.TextUnformatted("Copyright (C) 2012-2016, Erik de Castro Lopo <erikd@mega-nerd.com>\nAll rights reserved.");
    imgui.TextLinkOpenURL("https://libsndfile.github.io/libsamplerate/");
    
    imgui.SeparatorText("FLAC");
    imgui.TextUnformatted("Copyright (C) 2011-2024 Xiph.Org Foundation");
    imgui.TextLinkOpenURL("https://xiph.org/flac/");
    
    imgui.SeparatorText("Opus");
    imgui.TextUnformatted(
		`Copyright (C) 2001-2023 Xiph.Org, Skype Limited, Octasic,"
        Jean-Marc Valin, Timothy B. Terriberry,"
        CSIRO, Gregory Maxwell, Mark Borgerding,"
        Erik de Castro Lopo, Mozilla, Amazon`);
    imgui.TextLinkOpenURL("https://opus-codec.org/");
    
    imgui.SeparatorText("OGG");
    imgui.TextUnformatted("Copyright (C) 2002, Xiph.org Foundation");
    imgui.TextLinkOpenURL("https://www.xiph.org/ogg/");
    
    imgui.SeparatorText("libmp3lame");
    imgui.TextUnformatted("Copyright (C) 1999 Mark Taylor");
    imgui.TextLinkOpenURL("https://www.mp3dev.org/");
    
    imgui.SeparatorText("Vorbis");
    imgui.TextUnformatted("Copyright (C) 2002-2020 Xiph.org Foundation");
    imgui.TextLinkOpenURL("https://xiph.org/vorbis/");
    
    imgui.SeparatorText("mpg123");
    imgui.TextUnformatted("Copyright (C) 1995-2020 by Michael Hipp and others,\nfree software under the terms of the LGPL v2.1");
    imgui.TextLinkOpenURL("https://mpg123.de/");
    
    imgui.SeparatorText("FreeType");
    imgui.TextUnformatted("Copyright (C) 1996-2002, 2006 by\nDavid Turner, Robert Wilhelm, and Werner Lemberg");
    imgui.TextLinkOpenURL("https://freetype.org/");
    
    imgui.SeparatorText("Brotli");
    imgui.TextUnformatted("Copyright (C) 2009, 2010, 2013-2016 by the Brotli Authors.");
    imgui.TextLinkOpenURL("https://www.brotli.org/");
    
    imgui.SeparatorText("libpng");
    imgui.TextUnformatted("Copyright (C) 1995-2024 The PNG Reference Library Authors.");
    imgui.TextLinkOpenURL("http://www.libpng.org/pub/png/libpng.html");
    
    imgui.SeparatorText("TagLib");
    imgui.TextUnformatted("Copyright (C) 2002 - 2008 by Scott Wheeler");
    imgui.TextLinkOpenURL("https://taglib.org/");
    
    imgui.SeparatorText("zlib");
    imgui.TextUnformatted("Copyright (C) 1995-2024 Jean-loup Gailly and Mark Adler");
    imgui.TextLinkOpenURL("https://www.zlib.net/");
    
    imgui.SeparatorText("bzip2");
    imgui.TextUnformatted("Copyright (C) 1996-2019 Julian R Seward");
    imgui.TextLinkOpenURL("https://sourceware.org/bzip2/");

    imgui.SeparatorText("KISS FFT");
    imgui.TextUnformatted("Copyright (c) 2003-2010 Mark Borgerding . All rights reserved.");
    imgui.TextLinkOpenURL("https://github.com/mborgerding/kissfft");
}
