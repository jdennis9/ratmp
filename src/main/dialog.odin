package main

import "core:fmt"
Message_Box_Type :: enum {
	Message,
	OkCancel,
	YesNo,
	YesNoCancel,
}

Message_Box_Urgency :: enum {
	Info,
	Question,
	Warning,
	Error,
}

Message_Box_Response :: enum {
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
