package ffmpeg_2

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "../bindings.lib"
}
else {
	foreign import lib "../bindings.a"
}

MAX_AUDIO_CHANNELS :: 2

Packet :: struct {
	frames_in: i32,
	frames_out: i32,
	data: [MAX_AUDIO_CHANNELS][^]f32,
}

Audio_Spec :: struct {
	channels: i32,
	samplerate: i32,
}

File_Info :: struct {
	codec_name: [64]u8,
	format_name: [64]u8,
	spec: Audio_Spec,
	total_frames: i64,
}

Decode_Status :: enum c.int {
	Ok,
	Eof,
	NoFile,
	Error,
}

Context :: struct {}

@(link_prefix="ffmpeg_")
foreign lib {
	@require_results create_context :: proc() -> ^Context ---
	free_context :: proc(ctx: ^Context) ---
	open_input :: proc(ctx: ^Context, filename: cstring, info_out: ^File_Info) -> bool ---
	close_input :: proc(ctx: ^Context) ---
	is_open :: proc(ctx: ^Context) -> bool ---
	decode_packet :: proc(ctx: ^Context, output_spec: ^Audio_Spec, packet_out: ^Packet) -> Decode_Status ---
	free_packet :: proc(packet: ^Packet) ---
	seek_to_second :: proc(ctx: ^Context, second: i64) -> bool ---
	load_thumbnail :: proc(filename: cstring, data: ^rawptr, w: ^i32, h: ^i32) -> bool ---
	free_thumbnail :: proc(data: rawptr) ---
}
