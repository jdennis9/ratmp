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

import win "core:sys/windows"

dialog_init_windows :: proc() {
	_dialog_impl_show_message_box = proc(
		type: Message_Box_Type, urgency: Message_Box_Urgency, title, body: cstring
	) -> (res: Message_Box_Response, error: Error) {
		message_u16 := cstring16(raw_data(win.utf8_to_utf16_alloc(string(body), context.allocator)))
		defer delete(message_u16)
		title_u16 := cstring16(raw_data(win.utf8_to_utf16_alloc(string(title), context.allocator)))
		defer delete(title_u16)

		icon: win.UINT
		switch urgency {
		case .Info: icon = win.MB_ICONINFORMATION
		case .Question: icon = win.MB_ICONQUESTION
		case .Warning: icon = win.MB_ICONWARNING
		case .Error: icon = win.MB_ICONERROR
		}

		switch type {
		case .Message:
			win.MessageBoxW(nil, message_u16, title_u16, icon)
			return
		case .OkCancel:
			r := win.MessageBoxW(nil, message_u16, title_u16, icon | win.MB_OKCANCEL)
			switch r {
			case win.IDOK: res = .OkYes
			case win.IDCANCEL: res = .Cancel
			}
			return
		case .YesNo:
			r := win.MessageBoxW(nil, message_u16, title_u16, icon | win.MB_YESNO)
			switch r {
			case win.IDYES: res = .OkYes
			case win.IDNO: res = .No
			}
			return
		}


		return
	}
}
