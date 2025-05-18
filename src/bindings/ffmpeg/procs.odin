package ffmpeg

import "core:c"

COMPRESSION_DEFAULT ::  -1

when ODIN_OS == .Windows {
	foreign import lib {
		"avutil.lib",
		"avformat.lib",
		"avcodec.lib",
		"system:Secur32.lib",
		"system:strmiids.lib",
		"system:Mfplat.lib",
		"system:Mfuuid.lib",
		"system:Bcrypt.lib",
	}
}

@(link_prefix="av_")
foreign lib {
	log_set_level :: proc(level: c.int) ---
	get_bytes_per_sample :: proc(fmt: SampleFormat) -> c.int ---
	sample_fmt_is_planar :: proc(fmt: SampleFormat) -> c.int ---

	frame_alloc :: proc() -> ^Frame ---
	frame_unref :: proc(frame: ^Frame) ---
	frame_free :: proc(frame: ^^Frame) ---
	read_frame :: proc(ctx: ^FormatContext, packet: ^Packet) -> c.int ---
	
	packet_alloc :: proc() -> ^Packet ---
	packet_unref :: proc(packet: ^Packet) ---
	packet_free :: proc(packet: ^^Packet) ---

	channel_layout_default :: proc(layout: ^ChannelLayout, nb_channels: c.int) ---

	rescale :: proc(a, b, c: i64) -> i64 ---
}

@(link_prefix="av")
foreign lib {
	codec_parameters_to_context :: proc(codec: ^CodecContext, par: ^CodecParameters) -> c.int ---
	codec_find_decoder :: proc(id: CodecID) -> ^Codec ---
	codec_alloc_context3 :: proc(codec: ^Codec) -> ^CodecContext ---
	codec_free_context :: proc(ctx: ^^CodecContext) ---
	codec_open2 :: proc(ctx: ^CodecContext, codec: ^Codec, options: ^^Dictionary) -> c.int ---
	codec_close :: proc(ctx: ^CodecContext) -> c.int ---
	codec_send_packet :: proc(ctx: ^CodecContext, packet: ^Packet) -> c.int ---
	codec_receive_frame :: proc(ctx: ^CodecContext, frame: ^Frame) -> c.int ---
	codec_flush_buffers :: proc(ctx: ^CodecContext) ---

	format_alloc_context :: proc() -> ^FormatContext ---
	format_free_context :: proc(ctx: ^FormatContext) ---
	format_open_input :: proc(ctx: ^^FormatContext, filename: cstring, fmt: ^InputFormat, options: ^Dictionary) -> c.int ---
	format_close_input :: proc(ctx: ^^FormatContext) ---
	format_find_stream_info :: proc(ctx: ^FormatContext, options: ^^Dictionary) -> c.int ---
	format_seek_file :: proc(s: ^FormatContext, stream_index: c.int, min_ts, ts, max_ts: i64, flags: c.int) -> c.int ---
}
