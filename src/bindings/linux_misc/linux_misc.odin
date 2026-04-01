package linux_misc

import "core:c"

foreign import lib "../bindings.a"

Message_Type :: enum c.int {
	Message,
	YesNo,
	OkCancel,
}

Urgency :: enum c.int {
	Info,
	Question,
	Warning,
	Error,
}

Message_Response :: enum c.int {
	OkYes,
	No,
	Cancel,
}

Tray_Button :: struct {
	name: cstring,
	id: i32,
}

@(link_prefix="linux_misc_")
foreign lib {
	init :: proc() ---
	message_box :: proc(message: cstring, type: Message_Type, urgency: Urgency) -> Message_Response ---
	systray_init :: proc(
		event_handler: proc "c" (button: i32),
		buttons: [^]Tray_Button,
		button_count: i32
	) ---
	gtk_main_iteration :: proc(blocking: bool) ---
}
