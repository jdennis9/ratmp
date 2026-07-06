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
package media_controls

import "src:main/library"
import "src:main/shared"
import "src:main/player"

Command :: enum {
	Pause,
	Play,
	Stop,
	ShuffleOn,
	ShuffleOff,
	Next,
	Prev,
	RepeatTrack,
	RepeatPlaylist,
	RepeatOff,
}

Handler :: #type proc(data: rawptr, command: Command)

// all procs should only be called on the main thread
Interface :: struct {
	shutdown:     proc(),
	update_track: proc(track: library.Track),
	update_state: proc(state: player.State),
}

@(private="file")
_impl: Interface

@(private="file")
_handler: Handler

@(private="file")
_handler_data: rawptr

@private
set_impl :: proc(i: Interface) {_impl = i}

@private
handle_command :: proc(cmd: Command) {
	if _handler != nil {
		_handler(_handler_data, cmd)
	}
}

set_handler :: proc(h: Handler, data: rawptr) {
	_handler = h
	_handler_data = data
}
