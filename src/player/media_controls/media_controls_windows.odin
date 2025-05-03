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
package media_controls

foreign import lib "../../cpp/cpp.lib"

import "base:runtime"
import "core:c"

Event :: enum c.int {
	Pause,
	Play,
	Prev,
	Next,
}

Status :: enum c.int {
	Stopped,
	Paused,
	Playing,
}

@private
this: struct {
	ctx: runtime.Context,
}

Event_Handler :: #type proc "c" (event: Event)

@(link_prefix="media_controls_")
foreign lib {
	install_handler :: proc(handler: Event_Handler) -> bool ---
	set_status :: proc(status: Status) ---
	set_metadata :: proc(album: cstring, artist: cstring, title: cstring) ---
}
