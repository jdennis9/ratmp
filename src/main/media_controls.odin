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

import lib "src:main/library"

Media_Controls_Event :: enum {
	Play,
	Pause,
	Toggle,
	Stop,
	Next,
	Prev,
	EnableShuffle,
	DisableShuffle,
}

Media_Controls_State :: struct {
	paused:          bool,
	shuffle_enabled: bool,
	have_track:      bool,
}

Media_Controls_Track_Info :: struct {
	id:      Track_ID,
	title:   string,
	artists: string,
	genres:  string,
	album:   string,
	url:     string,
}

Media_Controls_Proc :: #type proc(data: rawptr, event: Media_Controls_Event)

_media_controls_impl_init:         proc(cb: Media_Controls_Proc, cbd: rawptr) -> bool
_media_controls_impl_update_track: proc(sv: ^Server, track: Media_Controls_Track_Info)
_media_controls_impl_update_state: proc(state: Media_Controls_State)
_media_controls_impl_destroy:      proc()

media_controls_init :: proc(cb: Media_Controls_Proc, cbd: rawptr) -> bool {
	if _media_controls_impl_init != nil {
		return _media_controls_impl_init(cb, cbd)
	}
	return true
}

media_controls_update_track :: proc(sv: ^Server, track: Track) {
	if _media_controls_impl_update_track != nil {
		info := Media_Controls_Track_Info {
			id      = track.handle,
			title   = track.title,
			url     = track.url,
			album   = lib.get_shared_string(.Album, track.album),
			artists = lib.join_shared_strings(.Artist, track.artists, sv.allocators.temp),
			genres  = lib.join_shared_strings(.Genre, track.genres, sv.allocators.temp),
		}

		_media_controls_impl_update_track(sv, info)
	}
}

media_controls_update_state :: proc(state: Media_Controls_State) {
	if _media_controls_impl_update_state != nil {
		_media_controls_impl_update_state(state)
	}
}

media_controls_destroy :: proc() {
	if _media_controls_impl_destroy != nil {
		_media_controls_impl_destroy()
	}
}
