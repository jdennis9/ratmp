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
package sys

import win "core:sys/windows"
import "core:unicode/utf16"

open_dialog :: proc(title: string, type: Dialog_Type, message: string) -> bool {
	message_u16: [512]u16
	title_u16: [64]u16

	utf16.encode_string(message_u16[:511], message)
	utf16.encode_string(title_u16[:63], title)

	message_cstr := cstring16(&message_u16[0])
	title_cstr := cstring16(&title_u16[0])

	switch type {
		case .Message: {
			win.MessageBoxW(nil, message_cstr, title_cstr, win.MB_ICONWARNING)
			return true
		}
		case .YesNo: {
			return win.MessageBoxW(nil, message_cstr, title_cstr,
				win.MB_ICONQUESTION|win.MB_YESNO) == win.IDYES
		}
		case .OkCancel: {
			return win.MessageBoxW(nil, message_cstr, title_cstr,
				win.MB_ICONQUESTION|win.MB_OKCANCEL) == win.IDOK
		}
	}

	return true
}

