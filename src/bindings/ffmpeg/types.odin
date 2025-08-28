package ffmpeg

import "core:c"

NUM_DATA_POINTERS :: 8
TIME_BASE :: 1000000

ERROR_EOF :: 0xdfb9b0bb

Rational :: struct {
	num: c.int,
	den: c.int,
}

Class :: struct {}

Dictionary :: struct {}

BufferRef :: struct {}

MediaType :: enum c.int {
	VIDEO,
	AUDIO,
	DATA,
	SUBTITLE,
	ATTACHMENT,
}
SampleFormat :: enum c.int {
	U8,
	S16,
	S32,
	FLT,
	DBL,
	U8P,
	S16P,
	S32P,
	FLTP,
	DBLP,
	S64,
	S64P,
}
FieldOrder :: enum c.int {}
Discard :: enum c.int {}

CodecParameters :: struct {
	codec_type: MediaType,
	codec_id: CodecID,
	codec_tag: u32,
	extradata: rawptr,
	extradata_size: c.int,
	coded_side_data: rawptr,
	nb_coded_side_data: c.int,
	format: SampleFormat,
	bit_rate: i64,
	bits_per_coded_sample: c.int,
	bits_per_raw_sample: c.int,
	profile: c.int,
	level: c.int,
	width: c.int,
	height: c.int,
	sample_aspect_ratio: Rational,
	framerate: Rational,
	field_order: FieldOrder,
	color_range: c.int,
	color_primaries: c.int,
	color_trc: c.int,
	color_space: c.int,
	chroma_location: c.int,
	video_delay: c.int,
	ch_layout: ChannelLayout,
	sample_rate: c.int,
	block_align: c.int,
	frame_size: c.int,
	initial_padding: c.int,
	trailing_padding: c.int,
	seek_preroll: c.int,
}

Stream :: struct {
    av_class: ^Class,
    index: c.int,
    id: c.int,
    codecpar: ^CodecParameters,
    priv_data: rawptr,
    time_base: Rational,
    start_time: i64,
    duration: i64,
    nb_frames: i64,
    disposition: c.int,
    discard: Discard,
    sample_aspect_ratio: Rational,
    metadata: ^Dictionary,
    avg_frame_rate: Rational,
    attached_pic: Packet,
	_: rawptr,
	_: c.int,
    event_flags: c.int,
    r_frame_rate: Rational,
    pts_wrap_bits: c.int,
}

ChannelOrder :: enum c.int {}

ChannelLayout :: struct {
	order: ChannelOrder,
	nb_channels: c.int,
	u: struct #raw_union {
		mask: u64,
		map_: rawptr,
	},
	opaque: rawptr,
}

Codec :: struct {
    /**
     * Name of the codec implementation.
     * The name is globally unique among encoders and among decoders (but an
     * encoder and a decoder can share the same name).
     * This is the primary way to find a codec from the user perspective.
     */
    name: cstring,
    /**
     * Descriptive name for the codec, meant to be more human readable than name.
     * You should use the NULL_IF_CONFIG_SMALL() macro to define it.
     */
    long_name: cstring,
    type: MediaType,
    id: CodecID,
    /**
     * Codec capabilities.
     * see AV_CODEC_CAP_*
     */
    capabilities: c.int,
    max_lowres: u8,

    /**
     * Deprecated codec capabilities.
     */
    supported_framerates: [^]Rational,
    pix_fmts: [^]PixelFormat,
    supported_samplerates: [^]c.int,
    sample_fmts: [^]SampleFormat,

    priv_class: ^Class,
    profiles: rawptr,
    wrapper_name: cstring,
    ch_layouts: [^]ChannelLayout,
}

Frame :: struct {
	data: [NUM_DATA_POINTERS][^]u8,
	linesize: [NUM_DATA_POINTERS]c.int,
	extended_data: [^][^]u8,
	width, height: c.int,
	nb_samples: c.int,
	format: c.int,
	key_frame: c.int,
	pict_type: enum c.int {},
	sample_aspect_ratio: Rational,
	pts: i64,
	pkt_dts: i64,
	time_base: Rational,
	quality: c.int,
	opaque: rawptr,
	repeat_pict: c.int,

	interlaced_frame: c.int,
	top_field_first: c.int,

	palette_has_changed: c.int,

	sample_rate: c.int,
	buf: [NUM_DATA_POINTERS]^BufferRef,
	extended_buf: [^]^BufferRef,
	nb_extended_buf: c.int,
	side_data: rawptr,
	nb_side_data: c.int,
	flags: c.int,
	color_range: c.int,
	color_primaries: c.int,
	color_trc: c.int,
	colorspace: c.int,
	chroma_location: c.int,
	best_effort_timestamp: i64,

	pkt_pos: i64,

	metadata: ^Dictionary,
	decode_error_flags: c.int,

	pkt_size: c.int,

	hw_frames_ctx: ^BufferRef,
	opaque_ref: ^BufferRef,
	crop_top: c.size_t,
	crop_bottom: c.size_t,
	crop_left: c.size_t,
	crop_right: c.size_t,
	private_ref: ^BufferRef,
	ch_layout: ChannelLayout,
	duration: i64,
}

Packet :: struct {
	buf: ^BufferRef,
	pts: i64,
	dts: i64,
	data: [^]u8,
	size: c.int,
	stream_index: c.int,
	flags: c.int,
	side_data: rawptr,
	side_data_elems: c.int,
	duration: i64,
	pos: i64,
	opaque: rawptr,
	opaque_ref: ^BufferRef,
	time_base: Rational,
}
