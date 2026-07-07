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

UI :: struct {
	library_scanner: lib.Scanner,

	windows: struct {
		library: struct {
			track_table: Track_Table,
		},
	}
}

@(private="file")
_ui: UI

ui_init :: proc() -> shared.Error {
	ui := &_ui

	lib.scanner_init(
		&ui.library_scanner,
		scanner_consume_proc,
		nil
	)

	return nil
}

ui_shutdown :: proc() {
	ui := &_ui
	lib.scanner_destroy(&ui.library_scanner)
}

ui_show :: proc() {
	ui := &_ui

	lib.lock()
	defer lib.unlock()

	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.PushStyleColor(.WindowBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor(2)

	_show_main_menu_bar()

	if imgui.Begin("Library") {
		tracks_serial := lib.get_tracks_serial()

		if !track_table_is_up_to_date(
			&ui.windows.library.track_table, tracks_serial, 0
		) {
			track_table_update(
				&ui.windows.library.track_table,
				tracks_serial,
				lib.get_all_track_ids(get_frame_allocator()),
				0
			)
		}

		track_table_show(&ui.windows.library.track_table, "##library", {})
	}
	imgui.End()
}

frame_allocator_guard :: runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD

@(private="file")
_show_main_menu_bar :: proc() -> bool {
	frame_allocator_guard()

	imgui.BeginMainMenuBar() or_return
	defer imgui.EndMainMenuBar()

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
	}

	return true
}

select_table_rows :: proc(table: ^$T, row_index: int, keep_selection: bool) {
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
