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
