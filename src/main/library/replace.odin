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

import "core:mem"
import "core:strings"

Track_Metadata_Replace_Target :: enum {
	URL,
	Title,
}

@private
replace_track_metadata :: proc(
	tracks:    []Track_ID,
	targets:   bit_set[Track_Metadata_Replace_Target],
	old_str:   string,
	new_str:   string,
	allocator: mem.Allocator
) {
	for track_id in tracks {
		track := get_track_ptr(track_id) or_continue
		for target in targets {
			switch target {
			case .URL: track.url, _     = strings.replace_all(track.url, old_str, new_str, allocator)
			case .Title: track.title, _ = strings.replace_all(track.title, old_str, new_str, allocator)
			}
		}
	}
}
