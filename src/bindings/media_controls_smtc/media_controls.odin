package media_controls_smtc

import "core:c"

foreign import lib "src:bindings/bindings.lib"

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
	artist: cstring,
	album: cstring,
	title: cstring,
	genre: cstring,
	cover_data: [^]byte,
	cover_data_size: u32,
}

Handler :: #type proc "c" (data: rawptr, signal: Signal)

@(link_prefix="smtc_")
foreign lib {
	create :: proc(handler: Handler, data: rawptr) ---
	destroy :: proc() ---
	set_state :: proc(#by_ptr state: State) ---
	set_track_info :: proc(#by_ptr info: Track_Info) ---
}
