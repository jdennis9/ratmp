package media_controls

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "src:bindings/bindings.lib"
}
else {
	foreign import lib "src:bindings/bindings.a"
}

Signal :: enum c.int {
	Play,
	Pause,
	Stop,
	Next,
	Prev,
}

State :: enum c.int {
	Playing,
	Paused,
	Stopped,
}

Handler :: #type proc "c" (data: rawptr, signal: Signal)

foreign lib {
	enable :: proc(handler: Handler, data: rawptr) ---
	disable :: proc() ---
	set_state :: proc(state: State) ---
	set_metadata :: proc(artist: cstring, album: cstring, title: cstring) ---
}
