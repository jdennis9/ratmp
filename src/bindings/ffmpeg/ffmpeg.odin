package ffmpeg_2

import "core:c"

when ODIN_OS == .Windows {
	// WHY!

	foreign import lib "../bindings.lib"
	@require foreign import "avcodec.lib"
	@require foreign import "avformat.lib"
	@require foreign import "avutil.lib"
	@require foreign import "swresample.lib"
	@require foreign import "swscale.lib"
	@require foreign import "opus.lib"
	@require foreign import mp3lame "libmp3lame-static.lib"
	@require foreign import "libpng16.lib"
	@require foreign import "vorbis.lib"
	@require foreign import "vorbisenc.lib"
	@require foreign import "vorbisfile.lib"
	@require foreign import "zlib.lib"
	@require foreign import "system:Secur32.lib"
	@require foreign import "system:User32.lib"
	@require foreign import "system:Ole32.lib"
	@require foreign import "system:mfplat.lib"
	@require foreign import "system:mfuuid.lib"
	@require foreign import "system:strmiids.lib"
}
else {
	foreign import lib "../bindings.a"
	@require foreign import "system:avcodec"
	@require foreign import "system:avformat"
	@require foreign import "system:avutil"
	@require foreign import "system:swresample"
	@require foreign import "system:swscale"
}

MAX_AUDIO_CHANNELS :: 2

Audio_Spec :: struct {
	channels:   i32,
	samplerate: i32,
}

Replay_Gain :: struct {
	track_gain, album_gain, track_peak, album_peak: f32,
}

Packet :: struct {
	frames_in:       i32,
	frames_out:      i32,
	data:            [MAX_AUDIO_CHANNELS][^]f32,
}

File_Info :: struct {
	codec_name:      [64]u8,
	format_name:     [64]u8,
	spec:            Audio_Spec,
	total_frames:    i64,
	has_replay_gain: bool,
	replay_gain:     Replay_Gain,
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
	@require_results
	create_context         :: proc() -> ^Context ---
	free_context           :: proc(ctx: ^Context) ---
	open_input             :: proc(ctx: ^Context, filename: cstring, info_out: ^File_Info) -> bool ---
	close_input            :: proc(ctx: ^Context) ---
	probe_codec_and_format :: proc(filename: cstring, codec_buf: cstring, format_buf: cstring, buf_size: i32) -> bool ---
	is_open                :: proc(ctx: ^Context) -> bool ---
	decode_packet          :: proc(ctx: ^Context, output_spec: ^Audio_Spec, packet_out: ^Packet) -> Decode_Status ---
	free_packet            :: proc(packet: ^Packet) ---
	seek_to_second         :: proc(ctx: ^Context, second: i64) -> bool ---
}
