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
package client

import "core:fmt"
import "src:imx"
import "base:runtime"
import "core:strings"
import "src:main/sys"
import "core:mem"
import "src:main/media_controls"
import "core:os"
import "core:flags"
import "src:main/shared"
import lib "src:main/library"
import "src:main/player"
import imgui "src:thirdparty/odin-imgui"

DEFAULT_FONT_CONFIG :: imgui.FontConfig {
	FontDataOwnedByAtlas = true,
	GlyphMaxAdvanceX = max(f32),
	RasterizerMultiply = 1,
	RasterizerDensity = 1,
	ExtraSizeScale = 1,
}

UI_Config :: struct {
	background_image: [512]u8,
	default_theme:    [128]u8,
	fonts:            [dynamic; 16]sys.System_Font,
	font_size:        f32,
}

UI_Window_Event :: enum {
	Show,
	Hidden,
	Free,
	SaveState,
	LoadState,
}

UI_Window :: struct {
	title:         string,
	internal_name: string,
	procedure:     proc(ev: UI_Window_Event) -> bool,
}

UI_Window_ID :: enum {
	Library,
	Queue,
	ThemeEditor,
	Metadata,
	Artists,
	Genres,
	Albums,
	Config,
	Spectrum,
	Wavebar,
}

UI_WINDOWS := [UI_Window_ID]UI_Window {
	.Library = {
		title         = "Library",
		internal_name = "_library",
		procedure     = library_window_proc,
	},
	.Queue = {
		title         = "Queue",
		internal_name = "_queue",
		procedure     = queue_window_proc,
	},
	.ThemeEditor = {
		title         = "Theme",
		internal_name = "_theme_editor",
		procedure     = theme_editor_window_proc,
	},
	.Metadata = {
		title         = "Metadata",
		internal_name = "_metadata",
		procedure     = metadata_window_proc,
	},
	.Artists = {
		title         = "Artists",
		internal_name = "_artists",
		procedure     = artists_window_proc,
	},
	.Albums = {
		title         = "Albums",
		internal_name = "_albums",
		procedure     = albums_window_proc,
	},
	.Genres = {
		title         = "Genres",
		internal_name = "_genres",
		procedure     = genres_window_proc,
	},
	.Config = {
		title         = "Settings",
		internal_name = "_settings",
		procedure     = config_editor_window_proc,
	},
	.Spectrum = {
		title         = "Spectrum",
		internal_name = "_spectrum",
		procedure     = spectrum_window_proc,
	},
	.Wavebar = {
		title         = "Wavebar",
		internal_name = "_wavebar",
		procedure     = wavebar_window_proc,
	},
}

UI_Window_State :: struct {
	shown:          bool,
	bring_to_front: bool,
}

UI :: struct {
	library_scanner: lib.Scanner,
	window_state:    [UI_Window_ID]UI_Window_State,
}

@(private="file")
_ui: UI

ui_init :: proc() -> shared.Error {
	ui := &_ui

	theme_init()

	lib.scanner_init(
		&ui.library_scanner,
		scanner_consume_proc,
		nil
	)

	for &ws in ui.window_state do ws.shown = true

	load_user_config()

	return nil
}

ui_shutdown :: proc() {
	ui := &_ui
	
	for win in UI_WINDOWS {
		win.procedure(.Free)
	}

	theme_shutdown()
	lib.scanner_destroy(&ui.library_scanner)
}

ui_apply_fonts :: proc() {
	io := imgui.GetIO()

	@static default_font := #load("../data/NotoSans-SemiBold.ttf")
	@static icon_font := #load("../data/Font Awesome 7 Free-Solid-900.otf")

	cfg := DEFAULT_FONT_CONFIG
	cfg.FontDataOwnedByAtlas = false
	
	imgui.FontAtlas_AddFontFromMemoryTTF(io.Fonts, raw_data(default_font), auto_cast len(default_font), font_cfg = &cfg)
	cfg.ExtraSizeScale = 0.8
	cfg.MergeMode = true
	imgui.FontAtlas_AddFontFromMemoryTTF(io.Fonts, raw_data(icon_font), auto_cast len(icon_font), font_cfg = &cfg)
}

ui_apply_config :: proc(cfg: ^UI_Config) {
	style := imgui.GetStyle()
	style.FontSizeBase = cfg.font_size

	set_theme_from_name(shared.string_from_array(cfg.default_theme[:]))

	ui_apply_fonts()
}

ui_show :: proc() {
	ui := &_ui

	temp_allocator := get_frame_allocator()

	lib.lock()
	defer lib.unlock()

	_show_main_menu_bar()
	_show_status_bar()

	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.PushStyleColor(.WindowBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor(2)

	// Show windows
	{
		frame_allocator_guard()
		
		for &state, id in ui.window_state {
			win := UI_WINDOWS[id]

			if !state.shown && !state.bring_to_front {
				win.procedure(.Hidden)
				continue
			}

			name := fmt.caprint(win.title, win.internal_name, sep="###", allocator=temp_allocator)

			if imgui.Begin(name, &state.shown) {
				win.procedure(.Show)
			}
			else {
				win.procedure(.Hidden)
			}
			imgui.End()
		}
	}
}

frame_allocator_guard :: runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD

@(private="file")
_show_main_menu_bar :: proc() -> bool {
	frame_allocator_guard()

	imgui.BeginMainMenuBar() or_return
	defer imgui.EndMainMenuBar()

	track_info := player.get_track_info()
	temp_allocator := get_frame_allocator()

	if imgui.BeginMenu("File") {
		defer imgui.EndMenu()

		if imgui.MenuItem("Add files") {
			frame_allocator_guard()

			audio_file_type := sys.File_Dialog_File_Type {
				extensions = lib.get_supported_extensions(temp_allocator),
				name       = "Supported Audio File",
			}

			image_file_type := sys.File_Dialog_File_Type {
				extensions = {".png", ".jpeg", ".jpg", ".webm", ".bmp", ".tga"},
				name       = "Supported Image File",
			}

			files, have_files := sys.show_file_dialog({
				select_multiple = true,
				file_types      = {audio_file_type, image_file_type},
			}, temp_allocator)

			if have_files {
				queue_files_for_scan(files, false)
			}
		}

		if imgui.MenuItem("Add folders") {
			frame_allocator_guard()

			folders, have_folders := sys.show_file_dialog({
				select_multiple = true,
				select_folders  = true,
			}, temp_allocator)

			if have_folders {
				queue_files_for_scan(folders, false)
			}
		}

		if imgui.MenuItem("Exit") do request_exit()
	}

	// --------------------------------------------------------------------------
	// Controls
	// --------------------------------------------------------------------------

	imgui.Separator()

	volume := player.get_volume() * 100
	imgui.SetNextItemWidth(80)
	if imgui.SliderFloat("##volume", &volume, 0, 100, "%.0f%%") {
		player.set_volume(volume / 100)
	}

	imgui.Separator()

	player_state := get_last_playback_state()
	shuffle_on := player.is_shuffle_on()

	if imgui.MenuItem(ICON_SHUFFLE, nil, shuffle_on) {
		player.set_shuffle_on(!shuffle_on)
	}

	if imgui.MenuItem(ICON_STOP) do player.stop_playback()
	if imgui.MenuItem(ICON_PREVIOUS_TRACK) do player.play_prev_track()

	if player_state.paused {
		if imgui.MenuItem(ICON_PLAY) do player.set_paused(false)
	}
	else {
		if imgui.MenuItem(ICON_PAUSE) do player.set_paused(true)
	}

	if imgui.MenuItem(ICON_NEXT_TRACK) do player.play_next_track()

	imgui.Separator()

	{
		track_pos := player.get_playback_pos()
		if imx.scrubber("##seek", &track_pos, 0, track_info.duration) {
			player.seek(track_pos)
		}
	}

	return true
}

@(private="file")
_show_status_bar :: proc() -> bool {
	defer imgui.End()
	imgui.BeginViewportSideBar("##status", imgui.GetMainViewport(), .Down, imgui.GetFrameHeight(), {
		.MenuBar, .NoSavedSettings, .NoScrollbar
	}) or_return
	imgui.BeginMenuBar() or_return
	defer imgui.EndMenuBar()

	frame_allocator_guard()

	playback_state := get_last_playback_state()
	temp_allocator := get_frame_allocator()

	track_info_block: if playback_state.track != nil {
		track   := lib.get_track(playback_state.track.?) or_break track_info_block
		info    := player.get_track_info()
		artists := lib.join_shared_strings(.Artist, track.artists, temp_allocator)

		imx.text_unformatted(artists)
		imx.text_unformatted("-")
		imx.text_unformatted(track.title)

		imgui.Separator()

		if track.album != nil do imx.text_unformatted(lib.get_shared_string(.Album, track.album.?))
		else do imgui.TextDisabled("No album")

		imgui.Separator()
		imx.text(32, info.samplerate, "Hz", sep="")

		imgui.Separator()
		imx.text(32, info.channels, "channels")

		imgui.Separator()
		imx.text_unformatted(lib.AUDIO_FILE_FORMAT_DISPLAY_NAMES[track.format].short)

		if info.replay_gain != nil {
			imgui.Separator()
			rp := info.replay_gain.?
			imx.textf(128, "Track gain/peak: %.2f dB / %.2f dB", rp.track_gain, rp.track_peak)
			imgui.Separator()
			imx.textf(128, "Album gain/peak: %.2f dB / %.2f dB", rp.album_gain, rp.album_peak)
		}
	}

	return true
}

select_table_rows :: proc(rows: []$T, row_index: int, keep_selection: bool) {
	row := &rows[row_index]
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

// Ensure that there is enough space for a resizable table to 
// prevent the bug where all columns have NaN width and ImGui explodes.
// Not sure if this actually works or not :/.
check_table_size :: proc() -> bool {
	s := imgui.GetContentRegionAvail()
	return s.x >= 50 && s.y >= 20
}

is_key_chord_pressed_in_window :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsWindowFocused({.ChildWindows}) && imgui.IsKeyChordPressed(auto_cast (mods | key))
}

is_key_chord_pressed :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsKeyChordPressed(auto_cast (mods | key))
}

scanner_consume_proc :: proc(_: rawptr, input: []lib.Scanned_Item) -> shared.Error {
	lib.lock()
	defer lib.unlock()

	shared.TIME_SCOPE("Add scanned tracks to library")

	for item in input {
		switch v in item.variant {
		case lib.Scanned_Track:
			lib.add_track(v.tags, v.url)
		case lib.Scanned_Art:
			lib.add_cover_art(v.folder, v.image)
		}
	}

	return nil
}

queue_files_for_scan :: proc(files: []string, overwrite: bool) {
	frame_allocator_guard()

	ui := &_ui
	items := lib.scanner_make_input(files, overwrite, get_frame_allocator())
	lib.scanner_queue(&ui.library_scanner, items)
}
