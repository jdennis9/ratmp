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
	EnableShuffle,
	DisableShuffle,
}

State :: struct {
	paused: bool,
	shuffle: bool,
	have_track: bool,
}

Track_Info :: struct {
	path: cstring,
	artist: cstring,
	album: cstring,
	title: cstring,
	genre: cstring,
	cover_data: [^]u8,
	cover_data_size: u32,
}

Handler :: #type proc "c" (data: rawptr, signal: Signal)

foreign lib {
	enable :: proc(handler: Handler, data: rawptr) ---
	disable :: proc() ---
	set_state :: proc(#by_ptr state: State) ---
	set_track_info :: proc(info: ^Track_Info) ---
}
