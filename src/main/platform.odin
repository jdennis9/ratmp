package main

Video_Impl :: enum {
	OpenGL,
	DX11,
}

Platform_Events :: struct {
	window_closed: bool,
	want_exit: bool,
}

// make_window should also choose graphics backend
_platform_impl_make_window: proc() -> bool
_platform_impl_destroy_window: proc()
_platform_impl_shutdown: proc()
_platform_impl_imgui_new_frame: proc()
_platform_impl_poll_events: proc() -> Platform_Events
_platform_impl_swap_buffers: proc()
_platform_impl_set_gl_proc_address: proc(p: rawptr, name: cstring)
_platform_impl_is_window_visible: proc() -> bool

platform_make_window :: proc() -> bool {
	return _platform_impl_make_window()
}

platform_destroy_window :: proc() {
	_platform_impl_destroy_window()
}

platform_imgui_new_frame :: proc() {
	_platform_impl_imgui_new_frame()
}

platform_swap_buffers :: proc() {
	_platform_impl_swap_buffers()
}

platform_poll_events :: proc() -> Platform_Events {
	return _platform_impl_poll_events()
}

platform_set_gl_proc_address :: proc(p: rawptr, name: cstring) {
	_platform_impl_set_gl_proc_address(p, name)
}

platform_is_window_visible :: proc() -> bool {
	return _platform_impl_is_window_visible()
}

platform_shutdown :: proc() {
	_platform_impl_shutdown()
}
