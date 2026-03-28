package main

import "core:thread"
import "src:bindings/linux_misc"

@(private="file")
_background_loop: ^thread.Thread

sys_main_init :: proc() -> bool {
	linux_misc.init()
	_background_loop = thread.create(_run_background_loop, .Low)
	_background_loop.init_context = context
	thread.start(_background_loop)
	return true
}

sys_main_frame :: proc() {
}

sys_main_shutdown :: proc() {
}


@(private="file")
_run_background_loop :: proc(t: ^thread.Thread) {
	for {
		linux_misc.gtk_main_iteration(true)
	}
}
