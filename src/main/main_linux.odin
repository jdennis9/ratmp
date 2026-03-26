package main

import "src:bindings/linux_misc"

sys_main_init :: proc() -> bool {
	linux_misc.init()
	return true
}

sys_main_frame :: proc() {
	linux_misc.update()
}

sys_main_shutdown :: proc() {
}
