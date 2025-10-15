package linux_misc

import "core:c"

foreign import lib "../bindings.a"

MESSAGE_TYPE_INFO :: 0
MESSAGE_TYPE_WARNING :: 1
MESSAGE_TYPE_YES_NO :: 2
MESSAGE_TYPE_OK_CANCEL :: 3

Systray_Event :: enum i32 {
	Show,
	Exit,
}

@(link_prefix="linux_misc_")
foreign lib {
	init :: proc() ---
	message_box :: proc(message: cstring, type: c.int) -> bool ---

	systray_init :: proc(event_handler: proc "c" (event: Systray_Event)) ---
	update :: proc() ---
}
