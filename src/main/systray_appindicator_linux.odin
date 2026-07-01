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
#+private file
package main

import "base:runtime"
import lm "src:bindings/linux_misc"

_systray_appindicator: struct {
	callback:      Sys_Tray_Proc,
	callback_data: rawptr,
	ctx:           runtime.Context,
}

_callback_wrapper :: proc "c" (in_button: i32) {
	context = _systray_appindicator.ctx
	button := cast(Sys_Tray_Button) in_button

	_systray_appindicator.callback(_systray_appindicator.callback_data, button)
}

@private
systray_use_linux_appindicator :: proc() {
	_systray_impl_create = proc(cb: Sys_Tray_Proc, cbd: rawptr) -> bool {
		_systray_appindicator.callback = cb
		_systray_appindicator.callback_data = cbd
		_systray_appindicator.ctx = context

		buttons := []lm.Tray_Button {
			{"Show", auto_cast Sys_Tray_Button.Show},
			{"Pause", auto_cast Sys_Tray_Button.Pause},
			{"Resume", auto_cast Sys_Tray_Button.Resume},
			{"Previous", auto_cast Sys_Tray_Button.Prev},
			{"Next", auto_cast Sys_Tray_Button.Next},
			{"Exit", auto_cast Sys_Tray_Button.Exit},
		}

		lm.systray_init(
			_callback_wrapper,
			raw_data(buttons),
			auto_cast len(buttons)
		)
		return true
	}

	_systray_impl_destroy = proc() {
	}
}
