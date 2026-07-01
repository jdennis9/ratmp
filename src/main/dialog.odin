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

Message_Box_Type :: enum {
	Message,
	OkCancel,
	YesNo,
}

Message_Box_Urgency :: enum {
	Info,
	Question,
	Warning,
	Error,
}

Message_Box_Response :: enum {
	None,
	OkYes,
	No,
	Cancel,
}


_dialog_impl_show_message_box: proc(
	type: Message_Box_Type, urgency: Message_Box_Urgency, title, body: cstring
) -> (Message_Box_Response, Error)

show_message_box :: proc(
	type: Message_Box_Type, urgency: Message_Box_Urgency,
	title: cstring, body_args: ..any, sep := " "
) -> (Message_Box_Response, Error) {
	buf: [1024]u8
	if _dialog_impl_show_message_box == nil do return .OkYes, Custom_Error.NotImplemented
	fmt.bprint(buf[:1023], ..body_args, sep=sep)
	return _dialog_impl_show_message_box(type, urgency, title, cstring(&buf[0]))
}
