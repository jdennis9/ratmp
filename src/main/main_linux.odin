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

import "core:thread"
import "src:bindings/linux_misc"

@(private="file")
_background_loop: ^thread.Thread

sys_main_init :: proc() -> bool {
	linux_misc.init()
	_background_loop = thread.create(_run_background_loop, .Low)
	_background_loop.init_context = context
	thread.start(_background_loop)
	return true
}

sys_main_frame :: proc() {
	linux_misc.gtk_main_iteration(false)
}

sys_main_shutdown :: proc() {
}


@(private="file")
_run_background_loop :: proc(t: ^thread.Thread) {
	/*for {
		linux_misc.gtk_main_iteration(true)
	}*/
}
