package util

import "core:c"
import "core:sys/posix"
import "core:strings"
import "core:fmt"

foreign import cpp {
	"../../cpp/cpp.a",
}

@(private="file")
MESSAGE_TYPE_INFO :: 0
@(private="file")
MESSAGE_TYPE_WARNING :: 1
@(private="file")
MESSAGE_TYPE_YES_NO :: 2
@(private="file")
MESSAGE_TYPE_OK_CANCEL :: 3

foreign cpp {
	show_message_box_gtk :: proc(message: cstring, type: c.int) -> bool ---
}

message_box :: proc(title: string, type: Message_Box_Type, message: string) -> bool {
	message_cstring := strings.clone_to_cstring(message)
	defer delete(message_cstring)

	switch type {
		case .Message:
			return show_message_box_gtk(message_cstring, MESSAGE_TYPE_INFO)
		case .OkCancel:
			return show_message_box_gtk(message_cstring, MESSAGE_TYPE_OK_CANCEL)
		case .YesNo:
			return show_message_box_gtk(message_cstring, MESSAGE_TYPE_YES_NO)
	}
	
	return false
}
