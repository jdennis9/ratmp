package ffmpeg

import "core:c"

CodecInternal :: struct {}
PixelFormat :: enum c.int {
	YUV420P,   ///< planar YUV 4:2:0, 12bpp, (1 Cr & Cb sample per 2x2 Y samples)
    YUYV422,   ///< packed YUV 4:2:2, 16bpp, Y0 Cb Y1 Cr
    RGB24,     ///< packed RGB 8:8:8, 24bpp, RGBRGB...
    BGR24,     ///< packed RGB 8:8:8, 24bpp, BGRBGR...
    YUV422P,   ///< planar YUV 4:2:2, 16bpp, (1 Cr & Cb sample per 2x1 Y samples)
    YUV444P,   ///< planar YUV 4:4:4, 24bpp, (1 Cr & Cb sample per 1x1 Y samples)
    YUV410P,   ///< planar YUV 4:1:0,  9bpp, (1 Cr & Cb sample per 4x4 Y samples)
    YUV411P,   ///< planar YUV 4:1:1, 12bpp, (1 Cr & Cb sample per 4x1 Y samples)
    GRAY8,     ///<        Y        ,  8bpp
    MONOWHITE, ///<        Y        ,  1bpp, 0 is white, 1 is black, in each byte pixels are ordered from the msb to the lsb
    MONOBLACK, ///<        Y        ,  1bpp, 0 is black, 1 is white, in each byte pixels are ordered from the msb to the lsb
    PAL8,      ///< 8 bits with AV_PIX_FMT_RGB32 palette
    YUVJ420P,  ///< planar YUV 4:2:0, 12bpp, full scale (JPEG), deprecated in favor of AV_PIX_FMT_YUV420P and setting color_range
    YUVJ422P,  ///< planar YUV 4:2:2, 16bpp, full scale (JPEG), deprecated in favor of AV_PIX_FMT_YUV422P and setting color_range
    YUVJ444P,  ///< planar YUV 4:4:4, 24bpp, full scale (JPEG), deprecated in favor of AV_PIX_FMT_YUV444P and setting color_range
    UYVY422,   ///< packed YUV 4:2:2, 16bpp, Cb Y0 Cr Y1
    UYYVYY411, ///< packed YUV 4:1:1, 12bpp, Cb Y0 Y1 Cr Y2 Y3
    BGR8,      ///< packed RGB 3:3:2,  8bpp, (msb)2B 3G 3R(lsb)
    BGR4,      ///< packed RGB 1:2:1 bitstream,  4bpp, (msb)1B 2G 1R(lsb), a byte contains two pixels, the first pixel in the byte is the one composed by the 4 msb bits
    BGR4_BYTE, ///< packed RGB 1:2:1,  8bpp, (msb)1B 2G 1R(lsb)
    RGB8,      ///< packed RGB 3:3:2,  8bpp, (msb)3R 3G 2B(lsb)
    RGB4,      ///< packed RGB 1:2:1 bitstream,  4bpp, (msb)1R 2G 1B(lsb), a byte contains two pixels, the first pixel in the byte is the one composed by the 4 msb bits
    RGB4_BYTE, ///< packed RGB 1:2:1,  8bpp, (msb)1R 2G 1B(lsb)
    NV12,      ///< planar YUV 4:2:0, 12bpp, 1 plane for Y and 1 plane for the UV components, which are interleaved (first byte U and the following byte V)
    NV21,      ///< as above, but U and V bytes are swapped
    ARGB,      ///< packed ARGB 8:8:8:8, 32bpp, ARGBARGB...
    RGBA,      ///< packed RGBA 8:8:8:8, 32bpp, RGBARGBA...
    ABGR,      ///< packed ABGR 8:8:8:8, 32bpp, ABGRABGR...
    BGRA,      ///< packed BGRA 8:8:8:8, 32bpp, BGRABGRA...
}

CodecContext :: struct {
	av_class: ^Class,
	log_level_offset: c.int,
	codec_type: MediaType,
	codec: ^Codec,
	codec_id: CodecID,
	codec_tag: c.uint,
	priv_data: rawptr,
	internal: ^CodecInternal,
	opaque: rawptr,
	bit_rate: i64,
	flags: c.int,
	flags2: c.int,
	extradata: [^]u8,
	extradata_size: c.int,
	time_base: Rational,
	pkt_timebase: Rational,
	framerate: Rational,
	_: c.int, // ticks_per_frame
	delay: c.int,
	width, height: c.int,
	coded_width, coded_height: c.int,
	sample_aspect_ratio: Rational,
	pix_fmt: PixelFormat,
	sw_pix_fmt: PixelFormat,
	color_primaries: c.int,
	color_trc: c.int,
	colorspace: c.int,
	color_range: c.int,
	chroma_sample_location: c.int,
	field_order: FieldOrder,
	refs: c.int,
	has_b_frames: c.int,
	slice_flags: c.int,

	/*void (*draw_horiz_band)(struct AVCodecContext *s,
							const AVFrame *src, int offset[AV_NUM_DATA_POINTERS],
							int y, int type, int height),*/
	draw_horiz_band: rawptr,

	//enum AVPixelFormat (*get_format)(struct AVCodecContext *s, const enum AVPixelFormat * fmt),
	get_format: rawptr,

	max_b_frames: c.int,
	b_quant_factor: f32,
	b_quant_offset: f32,
	i_quant_factor: f32,
	i_quant_offset: f32,
	lumi_masking: f32,
	temporal_cplx_masking: f32,
	spatial_cplx_masking: f32,
	p_masking: f32,
	dark_masking: f32,
	nsse_weight: c.int,
	me_cmp: c.int,
	me_sub_cmp: c.int,
	mb_cmp: c.int,
	ildct_cmp: c.int,
	dia_size: c.int,
	last_predictor_count: c.int,
	me_pre_cmp: c.int,
	pre_dia_size: c.int,
	me_subpel_quality: c.int,
	me_range: c.int,
	mb_decision: c.int,
	intra_matrix: [^]u16,
	inter_matrix: [^]u16,
	chroma_intra_matrix: [^]u16,
	intra_dc_precision: c.int,
	mb_lmin: c.int,
	mb_lmax: c.int,
	bidir_refine: c.int,
	keyint_min: c.int,
	gop_size: c.int,
	mv0_threshold: c.int,
	slices: c.int,
	sample_rate: c.int,
	sample_fmt: SampleFormat,  ///< sample format
	ch_layout: ChannelLayout,
	frame_size: c.int,
	block_align: c.int,
	cutoff: c.int,
	audio_service_type: enum c.int {},

	request_sample_fmt: SampleFormat,

	initial_padding: c.int,
	trailing_padding: c.int,
	seek_preroll: c.int,

	//int (*get_buffer2)(struct AVCodecContext *s, AVFrame *frame, int flags),
	get_buffer2: rawptr,
	bit_rate_tolerance: c.int,
	global_quality: c.int,
	compression_level: c.int,
	qcompress: f32,
	qblur: f32,
	qmin: c.int,
	qmax: c.int,
	max_qdiff: c.int,
	rc_buffer_size: c.int,
	rc_override_count: c.int,
	rc_override: rawptr,
	rc_max_rate: i64,
	rc_min_rate: i64,
	rc_max_available_vbv_use: f32,
	rc_min_vbv_overflow_use: f32,
	rc_initial_buffer_occupancy: c.int,
	trellis: c.int,
	stats_out: [^]u8,
	stats_in: [^]u8,
	workaround_bugs: c.int,
	strict_std_compliance: c.int,
	error_concealment: c.int,
	debug: c.int,
	err_recognition: c.int,
	//const struct AVHWAccel *hwaccel,
	hwaccel: rawptr,
	hwaccel_context: rawptr,
	hw_frames_ctx: ^BufferRef,
	hw_device_ctx: ^BufferRef,
	hwaccel_flags: c.int,
	extra_hw_frames: c.int,
	error: [NUM_DATA_POINTERS]u64,
	dct_algo: c.int,
	idct_algo: c.int,

	bits_per_coded_sample: c.int,
	bits_per_raw_sample: c.int,
	thread_count: c.int,
	thread_type: c.int,
	active_thread_type: c.int,

	//int (*execute)(struct AVCodecContext *c, int (*func)(struct AVCodecContext *c2, void *arg), void *arg2, int *ret, int count, int size),
	execute: rawptr,
	//int (*execute2)(struct AVCodecContext *c, int (*func)(struct AVCodecContext *c2, void *arg, int jobnr, int threadnr), void *arg2, int *ret, int count),
	execute2: rawptr,

	profile: c.int,

	/**
	 * Encoding level descriptor.
	 * - encoding: Set by user, corresponds to a specific level defined by the
	 *   codec, usually corresponding to the profile level, if not specified it
	 *   is set to FF_LEVEL_UNKNOWN.
	 * - decoding: Set by libavcodec.
	 * See AV_LEVEL_* in defs.h.
	 */
	level: c.int,

	/**
	 * Properties of the stream that gets decoded
	 * - encoding: unused
	 * - decoding: set by libavcodec
	 */
	properties: c.uint,

	/**
	 * Skip loop filtering for selected frames.
	 * - encoding: unused
	 * - decoding: Set by user.
	 */
	skip_loop_filter: Discard,
	skip_idct: Discard,
	skip_frame: Discard,

	skip_alpha: c.int,
	skip_top: c.int,
	skip_bottom: c.int,
	lowres: c.int,

	//const struct AVCodecDescriptor *codec_descriptor,
	codec_descriptor: rawptr,

	sub_charenc: [^]u8,
	sub_charenc_mode: c.int,

	subtitle_header_size: c.int,
	subtitle_header: [^]u8,

	dump_separator: [^]u8,

	/**
	 * ',' separated list of allowed decoders.
	 * If NULL then all are allowed
	 * - encoding: unused
	 * - decoding: set by user
	 */
	codec_whitelist: [^]u8,

	/**
	 * Additional data associated with the entire coded stream.
	 *
	 * - decoding: may be set by user before calling avcodec_open2().
	 * - encoding: may be set by libavcodec after avcodec_open2().
	 */
	//AVPacketSideData *coded_side_data,
	coded_side_data: rawptr,
	nb_coded_side_data: c.int,

	export_side_data: c.int,

	max_pixels: i64,

	apply_cropping: c.int,

	discard_damaged_percentage: c.int,

	max_samples: i64,

	//int (*get_encode_buffer)(struct AVCodecContext *s, AVPacket *pkt, int flags),
	get_encode_buffer: rawptr,

	frame_num: i64,

	side_data_prefer_packet: ^c.int,
	nb_side_data_prefer_packet: c.uint,

	//AVFrameSideData  **decoded_side_data,
	decoded_side_data: ^rawptr,
	nb_decoded_side_data: c.int,
}
