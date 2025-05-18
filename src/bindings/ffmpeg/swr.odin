package ffmpeg

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "swresample.lib"
}
else {
	foreign import lib "system:swresample"
}

SwrContext :: struct {}

foreign lib {
	swr_init :: proc(s: ^SwrContext) -> c.int ---
	swr_is_initialized :: proc(s: ^SwrContext) -> c.int ---
	swr_alloc_set_opts2 :: proc(
		ps: ^^SwrContext,
		out_ch_layout: ^ChannelLayout, out_sample_fmt: SampleFormat, out_sample_rate: c.int,
		in_ch_layout: ^ChannelLayout, in_sample_fmt: SampleFormat, in_sample_rate: c.int,
		log_offset: c.int, log_ctx: rawptr,
	) -> c.int ---
	swr_free :: proc(s: ^^SwrContext) ---
	// Returns number of frames output
	swr_convert :: proc(
		s: ^SwrContext,
		out: [^]rawptr,
		out_count: c.int,
		in_: [^]rawptr,
		in_count: c.int,
	) -> c.int ---
}
