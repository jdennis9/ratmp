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

import "core:fmt"

_notify_impl_send: proc(message: cstring) -> Error
_notify_impl_shutdown: proc()

notify_send :: proc(args: ..any, sep := " ") -> Error {
	if _notify_impl_send != nil {
		buf: [1024]u8
		fmt.bprint(buf[:1023], ..args, sep=sep)
		return _notify_impl_send(cstring(&buf[0]))
	}

	return nil
}

notify_shutdown :: proc() {
	if _notify_impl_shutdown != nil do _notify_impl_shutdown()
}
