#+private file
package main

gboolean :: b32

foreign import lib "system:notify"

Impl_Urgency :: enum i32 {
	Low,
	Normal,
	Critical,
}

Impl_Notification :: distinct rawptr

foreign lib {
	@(link_name="notify_init")
	impl_init :: proc(app_name: cstring) -> gboolean ---
	@(link_name="notify_uninit")
	impl_uninit :: proc() ---

	@(link_name="notify_notification_new")
	impl_new :: proc(summary, body, icon: cstring) -> Impl_Notification ---
	@(link_name="notify_notification_show")
	impl_show :: proc(not: Impl_Notification, error: rawptr) ---
	@(link_name="notify_notification_set_timeout")
	impl_set_timeout :: proc(not: Impl_Notification, timeout: i32) ---
	@(link_name="notify_notification_set_urgency")
	impl_set_urgency :: proc(not: Impl_Notification, urgency: Impl_Urgency) ---
	@(link_name="notify_notification_close")
	impl_close :: proc(noti: Impl_Notification, error: rawptr) -> gboolean ---
}

@private
notify_init_libnotify :: proc() -> Error {
	if !impl_init(PROGRAM_NAME) {
		return false
	}

	_notify_impl_send = proc(message: cstring) -> Error {
		not := impl_new(PROGRAM_NAME, message, PROGRAM_ID)
		if not == nil do return nil
		impl_set_urgency(not, .Low)
		impl_set_timeout(not, 5000)
		impl_show(not, nil)
		return nil
	}

	_notify_impl_shutdown = proc() {
		impl_uninit()
	}

	return nil
}

