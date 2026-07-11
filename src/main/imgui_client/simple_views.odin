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

import "src:main/player"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

library_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		track_table: Track_Table
	}

	if ev == .Free || ev == .Hidden {
		track_table_free(&w.track_table)
		return false
	}
	else if ev != .Show do return false

	tracks_serial := lib.get_tracks_serial()

	if !track_table_is_up_to_date(
		&w.track_table, tracks_serial, 0
	) {
		track_table_update(
			&w.track_table,
			tracks_serial,
			lib.get_all_track_ids(get_frame_allocator()),
			0
		)
	}

	track_table_show(&w.track_table, "##library", {})

	return true
}

queue_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		track_table: Track_Table
	}

	if ev == .Free || ev == .Hidden {
		track_table_free(&w.track_table)
		return false
	}
	else if ev != .Show do return false

	track_table_update(&w.track_table, player.get_queue_serial(), player.get_queue(), 1)
	track_table_show(&w.track_table, "##queue", {.IsQueue})

	return true
}
