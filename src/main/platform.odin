package main

import "core:strings"
import "core:fmt"
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
_platform_impl_wait_events: proc() -> Platform_Events
_platform_impl_swap_buffers: proc()
_platform_impl_is_window_visible: proc() -> bool
_platform_impl_set_window_visible: proc(visible: bool)
_platform_impl_flush_events: proc()
_platform_impl_set_window_title: proc(title: cstring)

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

platform_wait_events :: proc() -> Platform_Events {
	return _platform_impl_wait_events()
}

// Send an empty event to stop blocking on platform_wait_events
platform_flush_events :: proc() {
	_platform_impl_flush_events()
}

platform_is_window_visible :: proc() -> bool {
	return _platform_impl_is_window_visible()
}

platform_set_window_visible :: proc(visible: bool) {
	_platform_impl_set_window_visible(visible)
}

platform_shutdown :: proc() {
	_platform_impl_shutdown()
}

platform_set_window_title :: proc(args: ..any) {
	buf: [1024]u8
	str := fmt.bprint(buf[:1023], ..args)
	_platform_impl_set_window_title(strings.unsafe_string_to_cstring(str))
}
