package main

Sys_Tray_Button :: enum {
	Show,
	Pause,
	Resume,
	Prev,
	Next,
	Exit,
}

Sys_Tray_Proc :: #type proc(data: rawptr, button: Sys_Tray_Button)

_systray_impl_create: proc(callback: Sys_Tray_Proc, callback_data: rawptr) -> bool
_systray_impl_destroy: proc()

systray_create :: proc(callback: Sys_Tray_Proc, callback_data: rawptr) -> bool {
	if _systray_impl_create != nil {
		return _systray_impl_create(callback, callback_data)
	}
	return false
}

systray_destroy :: proc() {
	if _systray_impl_destroy != nil {
		_systray_impl_destroy()
	}
}
