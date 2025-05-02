package samplerate

import "core:c"

when ODIN_OS == .Windows {
	foreign import samplerate "samplerate.lib"
}
else {
	foreign import samplerate "system:samplerate"
}

Converter_Type :: enum c.int {
	SINC_BEST_QUALITY = 0,
	SINC_MEDIUM_QUALITY = 1,
	SINC_FASTEST = 2,
	ZERO_ORDER_HOLD = 3,
	LINEAR = 4,
}

Data :: struct {
	data_in: [^]f32,
	data_out: [^]f32,
	input_frames, output_frames: c.long,
	input_frames_used, output_frames_gen: c.long,
	end_of_input: c.int,
	src_ratio: f64,
}

State :: rawptr

@(link_prefix="src_")
foreign samplerate {
	new :: proc(converter_type: Converter_Type, channels: c.int, error: ^c.int) -> State ---
	delete :: proc(state: State) -> State ---
	process :: proc(state: State, data: ^Data) -> c.int ---
	reset :: proc(state: State) -> c.int ---
	set_ratio :: proc(state: State, ratio: f64) -> c.int ---
}

