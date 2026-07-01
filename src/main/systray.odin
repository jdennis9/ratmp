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

Sys_Tray_Button :: enum {
	None,
	Show,
	Pause,
	Resume,
	Prev,
	Next,
	Exit,
}

Sys_Tray_Proc :: #type proc(data: rawptr, button: Sys_Tray_Button)

_systray_impl_create: proc(callback: Sys_Tray_Proc, callback_data: rawptr) -> bool
_systray_impl_destroy: proc()

systray_create :: proc(callback: Sys_Tray_Proc, callback_data: rawptr) -> bool {
	if _systray_impl_create != nil {
		return _systray_impl_create(callback, callback_data)
	}
	return false
}

systray_destroy :: proc() {
	if _systray_impl_destroy != nil {
		_systray_impl_destroy()
	}
}
