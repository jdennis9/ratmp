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
package systray

Button :: enum {
	None,
	Show,
	Pause,
	Resume,
	Prev,
	Next,
	Exit,
}

Callback :: #type proc(data: rawptr, button: Button)

@private _impl_create: proc(callback: Callback, callback_data: rawptr) -> bool
@private _impl_destroy: proc()

init :: proc(callback: Callback, callback_data: rawptr) -> bool {
	if _impl_create != nil {
		return _impl_create(callback, callback_data)
	}
	return false
}

when ODIN_OS == .Windows {
	use_win32 :: proc() {
		_init_win32()
	}
}

when ODIN_OS == .Linux {
	use_appindicator :: proc() {
		_init_linux_appindicator()
	}
}

destroy :: proc() {
	if _impl_destroy != nil {
		_impl_destroy()
	}
}
