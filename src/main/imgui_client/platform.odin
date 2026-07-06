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

import "core:strings"
import "core:fmt"

Video_Impl :: enum {
	OpenGL,
	DX11,
}

Platform_Events :: struct {
	window_closed: bool,
	want_exit: bool,
}

// make_window should also choose graphics backend
_platform_impl_make_window:        proc() -> bool
_platform_impl_destroy_window:     proc()
_platform_impl_shutdown:           proc()
_platform_impl_imgui_new_frame:    proc()
_platform_impl_poll_events:        proc() -> Platform_Events
_platform_impl_wait_events:        proc() -> Platform_Events
_platform_impl_swap_buffers:       proc()
_platform_impl_is_window_visible:  proc() -> bool
_platform_impl_set_window_visible: proc(visible: bool)
_platform_impl_flush_events:       proc()
_platform_impl_set_window_title:   proc(title: cstring)
_platform_impl_set_window_size:    proc(w, h: int)

platform_make_window :: proc() -> bool {
	return _platform_impl_make_window()
}

platform_destroy_window :: proc() {
	_platform_impl_destroy_window()
}

platform_imgui_new_frame :: proc() {
	_platform_impl_imgui_new_frame()
}

platform_swap_buffers :: proc() {
	_platform_impl_swap_buffers()
}

platform_poll_events :: proc() -> Platform_Events {
	return _platform_impl_poll_events()
}

platform_wait_events :: proc() -> Platform_Events {
	return _platform_impl_wait_events()
}

// Send an empty event to stop blocking on platform_wait_events
platform_flush_events :: proc() {
	_platform_impl_flush_events()
}

platform_is_window_visible :: proc() -> bool {
	return _platform_impl_is_window_visible()
}

platform_set_window_visible :: proc(visible: bool) {
	_platform_impl_set_window_visible(visible)
}

platform_shutdown :: proc() {
	_platform_impl_shutdown()
}

platform_set_window_title :: proc(args: ..any) {
	buf: [1024]u8
	str := fmt.bprint(buf[:1023], ..args)
	_platform_impl_set_window_title(strings.unsafe_string_to_cstring(str))
}

platform_set_window_size :: proc(w, h: int) {
	_platform_impl_set_window_size(w, h)
}
