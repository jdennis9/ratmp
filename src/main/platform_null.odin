package main

import imgui "src:thirdparty/odin-imgui"
import "core:sync"

_null_platform: struct {
	event_signal: sync.Auto_Reset_Event,
}

platform_init_null :: proc() {
	video_init_null()
	
	_platform_impl_make_window = proc() -> bool {
		io := imgui.GetIO()
		io.BackendFlags |= {.HasMouseCursors, .RendererHasVtxOffset, .RendererHasTextures}
		return true
	}
	_platform_impl_destroy_window = proc() {
		io := imgui.GetIO()
		io.BackendFlags &= ~{.HasMouseCursors, .RendererHasVtxOffset, .RendererHasTextures}
	}
	_platform_impl_shutdown = proc() {}
	_platform_impl_imgui_new_frame = proc() {
		io := imgui.GetIO()
		io.DisplaySize = {1920, 1080}
		io.DeltaTime = 1.0 / 60.0
	}
	_platform_impl_poll_events = proc() -> Platform_Events {return {}}
	_platform_impl_wait_events = proc() -> Platform_Events {
		sync.auto_reset_event_wait(&_null_platform.event_signal)
		return {}
	}
	_platform_impl_swap_buffers = proc() {}
	_platform_impl_set_gl_proc_address = proc(p: rawptr, name: cstring) {}
	_platform_impl_is_window_visible = proc() -> bool {return false}
	_platform_impl_set_window_visible = proc(visible: bool) {}
	_platform_impl_flush_events = proc() {
		sync.auto_reset_event_signal(&_null_platform.event_signal)
	}
}
