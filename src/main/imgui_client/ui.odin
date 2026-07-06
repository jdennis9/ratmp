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
	frame_allocator:          mem.Allocator,
	frame_allocation_tracker: mem.Tracking_Allocator,
}

@(private="file")
_ui: UI

ui_init :: proc() -> shared.Error {
	ui := &_ui

	if launch_config.memory_debug {
		ui.frame_allocator = shared.track_allocator(
			context.temp_allocator, &ui.frame_allocation_tracker
		)
	}
	else {
		ui.frame_allocator = context.temp_allocator
	}

	return nil
}

ui_shutdown :: proc() {
}

ui_show :: proc() {
	ui := &_ui

	free_all(ui.frame_allocator)

	_show_main_menu_bar()

	@static tt: Track_Table

	track_table_show(
		&tt, "##library",
		lib.get_tracks_serial(),
		lib.get_all_track_ids(get_frame_allocator()),
		{},
		0
	)
}

get_frame_allocator :: proc() -> mem.Allocator {
	return _ui.frame_allocator
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

			file_type := sys.File_Dialog_File_Type {
				extensions = lib.get_supported_extensions(temp_allocator),
				name       = "Supported Audio File",
			}

			files, have_files := sys.show_file_dialog({
				select_multiple = true,
				file_types      = {file_type},
			}, temp_allocator)

			if have_files {
				for file in files {
					tags := lib.read_tags(file, temp_allocator) or_continue
					lib.add_track(tags, strings.concatenate({"file://", file}, temp_allocator))
				}
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

