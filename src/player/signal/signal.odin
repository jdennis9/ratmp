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
package events

import "core:log"

Signal :: enum {
	None,
	Exit,
	ReloadFont,
	TrackChanged,
	PlaybackStopped,
	PlaybackStateChanged,
	RequestPause,
	RequestPlay,
	RequestPrev,
	RequestNext,
	ApplyPrefs,
	CloseWindow,
	Iconify,
	NewFrame,
}

Signal_Handler :: #type proc(sig: Signal)
Post_Callback :: #type proc(sig: Signal)

@private
_handlers: [dynamic]Signal_Handler

@private
_post_callback: Post_Callback

// Platform backend needs to initialize this and provide a callback
// to post signal events
init :: proc(post_callback: Post_Callback) {
	_post_callback = post_callback
}

install_handler :: proc(handler: Signal_Handler) {
	append(&_handlers, handler)
}

post :: proc(sig: Signal, loc := #caller_location) {
	if sig != .NewFrame {
		log.debug(loc, sig)
		_post_callback(sig)
	}
	else {
		broadcast_immediate(sig)
	}
}

broadcast_immediate :: proc(sig: Signal) {
	if sig != .NewFrame {log.debug("Broadcast", sig)}
	for h in _handlers {
		h(sig)
	}
}
