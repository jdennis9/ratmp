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
package library

import "core:strings"
import "core:os"
import "core:thread"

@(private="file")
_do_scan :: proc(output: ^[dynamic]Track_ID) {
	iter := make_track_iterator()

	lock_for_read()

	reserve(output, get_track_count())

	for track in iterate_tracks(&iter) {
		if !strings.starts_with(track.url, "file://") do continue

		if !os.exists(strings.trim_prefix(track.url, "file://")) {
			append(output, track.handle)
		}
	}

	unlock_for_read()
}

@(private="file")
_scan_proc :: proc() {
	result: [dynamic]Track_ID
	defer delete(result)

	_do_scan(&result)

	send_event(Update_Missing_Tracks_Event {
		tracks = result[:]
	})
}

@(private="file")
_scan_and_remove_proc :: proc() {
	result: [dynamic]Track_ID
	defer delete(result)

	_do_scan(&result)

	send_event(Remove_Tracks_Event {
		tracks = result[:]
	})
}


start_missing_tracks_scan :: proc() {
	thread.run(_scan_proc, context)
}

scan_and_remove_missing_tracks :: proc() {
	thread.run(_scan_and_remove_proc, context)
}

