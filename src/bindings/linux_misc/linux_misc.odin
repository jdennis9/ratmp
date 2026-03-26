package linux_misc

import "core:c"

foreign import lib "../bindings.a"

Message_Type :: enum c.int {
	Info,
	Warning,
	YesNo,
	OkCancel,
}

Systray_Event :: enum i32 {
	Show,
	Exit,
}

@(link_prefix="linux_misc_")
foreign lib {
	init :: proc() ---
	message_box :: proc(message: cstring, type: Message_Type) -> bool ---
	systray_init :: proc(event_handler: proc "c" (event: Systray_Event)) ---
	update :: proc() ---
}
