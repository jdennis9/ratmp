package main

import "core:fmt"

_notify_impl_send: proc(message: cstring) -> Error
_notify_impl_shutdown: proc()

notify_send :: proc(args: ..any, sep := " ") -> Error {
	if _notify_impl_send != nil {
		buf: [1024]u8
		fmt.bprint(buf[:1023], ..args, sep=sep)
		return _notify_impl_send(cstring(&buf[0]))
	}

	return nil
}

notify_shutdown :: proc() {
	if _notify_impl_shutdown != nil do _notify_impl_shutdown()
}
