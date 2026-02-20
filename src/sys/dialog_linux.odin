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

import "core:c"
import "core:sys/posix"
import "core:c/libc"

import misc "src:bindings/linux_misc"

open_dialog :: proc(title: string, type: Dialog_Type, message: string) -> bool {
	message_buf: [2048]u8
	binding_type: c.int

	copy(message_buf[:2047], message)
	message_cstring := cstring(&message_buf[0])

	switch type {
		case .Message: binding_type = misc.MESSAGE_TYPE_INFO
		case .OkCancel: binding_type = misc.MESSAGE_TYPE_OK_CANCEL
		case .YesNo: binding_type = misc.MESSAGE_TYPE_YES_NO
	}

	return misc.message_box(message_cstring, binding_type)
}
