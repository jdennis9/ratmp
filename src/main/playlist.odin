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
package main

import hm "core:container/handle_map"
import "core:slice"

Playlist_Handle :: hm.Handle32

Playlist :: struct {
	handle:       Playlist_Handle,
	uid:          UID,
	name:         string,
	name_cstring: cstring,
	tracks:       [dynamic]Track_ID,
	serial:       uint,
}

playlist_add :: proc(sv: ^Server, pl: ^Playlist, tracks: []Track_ID) {
	for track_id in tracks {
		if slice.contains(pl.tracks[:], track_id) do continue
		append(&pl.tracks, track_id)
	}

	pl.serial += 1
}

playlist_remove :: proc(sv: ^Server, pl: ^Playlist, tracks: []Track_ID) {
	for track_id in tracks {
		index := slice.linear_search(pl.tracks[:], track_id) or_continue
		ordered_remove(&pl.tracks, index)
	}

	pl.serial += 1
}
