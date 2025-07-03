package media_controls

import "core:c"

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

enable :: proc(handler: Handler, data: rawptr) {
}

disable :: proc()  {
}

set_state :: proc(state: State) {
}

set_metadata :: proc(artist: cstring, album: cstring, title: cstring) {
}

