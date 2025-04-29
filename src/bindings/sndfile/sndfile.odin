package sndfile

import "core:c"
import "core:c/libc"

when ODIN_OS == .Windows {
	foreign import sndfile {
		"sndfile.lib",
		"FLAC.lib",
		"libmp3lame-static.lib",
		"libmpghip-static.lib",
		"mpg123.lib",
		"ogg.lib",
		"opus.lib",
		"vorbis.lib",
		"vorbisenc.lib",
		"vorbisfile.lib",
		"system:shlwapi.lib",
	}
}
else {
	foreign import sndfile {
		"system:sndfile",
	}
}

Format_Bits :: enum c.int {
	WAV			= 0x010000,		/* Microsoft WAV format (little endian default). */
	AIFF			= 0x020000,		/* Apple/SGI AIFF format (big endian). */
	AU			= 0x030000,		/* Sun/NeXT AU format (big endian). */
	RAW			= 0x040000,		/* RAW PCM data. */
	PAF			= 0x050000,		/* Ensoniq PARIS file format. */
	SVX			= 0x060000,		/* Amiga IFF / SVX8 / SV16 format. */
	NIST			= 0x070000,		/* Sphere NIST format. */
	VOC			= 0x080000,		/* VOC files. */
	IRCAM			= 0x0A0000,		/* Berkeley/IRCAM/CARL */
	W64			= 0x0B0000,		/* Sonic Foundry's 64 bit RIFF/WAV */
	MAT4			= 0x0C0000,		/* Matlab (tm) V4.2 / GNU Octave 2.0 */
	MAT5			= 0x0D0000,		/* Matlab (tm) V5.0 / GNU Octave 2.1 */
	PVF			= 0x0E0000,		/* Portable Voice Format */
	XI			= 0x0F0000,		/* Fasttracker 2 Extended Instrument */
	HTK			= 0x100000,		/* HMM Tool Kit format */
	SDS			= 0x110000,		/* Midi Sample Dump Standard */
	AVR			= 0x120000,		/* Audio Visual Research */
	WAVEX			= 0x130000,		/* MS WAVE with WAVEFORMATEX */
	SD2			= 0x160000,		/* Sound Designer 2 */
	FLAC			= 0x170000,		/* FLAC lossless file format */
	CAF			= 0x180000,		/* Core Audio File format */
	WVE			= 0x190000,		/* Psion WVE format */
	OGG			= 0x200000,		/* Xiph OGG container */
	MPC2K			= 0x210000,		/* Akai MPC 2000 sampler */
	RF64			= 0x220000,		/* RF64 WAV file */
	MPEG			= 0x230000,		/* MPEG-1/2 audio stream */

	/* Subtypes from here on. */

	PCM_S8		= 0x0001,		/* Signed 8 bit data */
	PCM_16		= 0x0002,		/* Signed 16 bit data */
	PCM_24		= 0x0003,		/* Signed 24 bit data */
	PCM_32		= 0x0004,		/* Signed 32 bit data */

	PCM_U8		= 0x0005,		/* Unsigned 8 bit data (WAV and RAW only) */

	FLOAT			= 0x0006,		/* 32 bit float data */
	DOUBLE		= 0x0007,		/* 64 bit float data */

	ULAW			= 0x0010,		/* U-Law encoded. */
	ALAW			= 0x0011,		/* A-Law encoded. */
	IMA_ADPCM		= 0x0012,		/* IMA ADPCM. */
	MS_ADPCM		= 0x0013,		/* Microsoft ADPCM. */

	GSM610		= 0x0020,		/* GSM 6.10 encoding. */
	VOX_ADPCM		= 0x0021,		/* OKI / Dialogix ADPCM */

	NMS_ADPCM_16	= 0x0022,		/* 16kbs NMS G721-variant encoding. */
	NMS_ADPCM_24	= 0x0023,		/* 24kbs NMS G721-variant encoding. */
	NMS_ADPCM_32	= 0x0024,		/* 32kbs NMS G721-variant encoding. */

	G721_32		= 0x0030,		/* 32kbs G721 ADPCM encoding. */
	G723_24		= 0x0031,		/* 24kbs G723 ADPCM encoding. */
	G723_40		= 0x0032,		/* 40kbs G723 ADPCM encoding. */

	DWVW_12		= 0x0040, 		/* 12 bit Delta Width Variable Word encoding. */
	DWVW_16		= 0x0041, 		/* 16 bit Delta Width Variable Word encoding. */
	DWVW_24		= 0x0042, 		/* 24 bit Delta Width Variable Word encoding. */
	DWVW_N		= 0x0043, 		/* N bit Delta Width Variable Word encoding. */

	DPCM_8		= 0x0050,		/* 8 bit differential PCM (XI only) */
	DPCM_16		= 0x0051,		/* 16 bit differential PCM (XI only) */

	VORBIS		= 0x0060,		/* Xiph Vorbis encoding. */
	OPUS			= 0x0064,		/* Xiph/Skype Opus encoding. */

	ALAC_16		= 0x0070,		/* Apple Lossless Audio Codec (16 bit). */
	ALAC_20		= 0x0071,		/* Apple Lossless Audio Codec (20 bit). */
	ALAC_24		= 0x0072,		/* Apple Lossless Audio Codec (24 bit). */
	ALAC_32		= 0x0073,		/* Apple Lossless Audio Codec (32 bit). */

	MPEG_LAYER_I	= 0x0080,		/* MPEG-1 Audio Layer I */
	MPEG_LAYER_II	= 0x0081,		/* MPEG-1 Audio Layer II */
	MPEG_LAYER_III = 0x0082,		/* MPEG-2 Audio Layer III */

	/* Endian-ness options. */

	ENDIAN_FILE			= 0x00000000,	/* Default file endian-ness. */
	ENDIAN_LITTLE		= 0x10000000,	/* Force little endian-ness. */
	ENDIAN_BIG			= 0x20000000,	/* Force big endian-ness. */
	ENDIAN_CPU			= 0x30000000,	/* Force CPU endian-ness. */

	SUBMASK		= 0x0000FFFF,
	TYPEMASK		= 0x0FFF0000,
	ENDMASK		= 0x30000000
}

Channel :: enum c.int {
	INVALID = 0,
	MONO = 1,
	LEFT,					/* Apple calls this 'Left' */
	RIGHT,					/* Apple calls this 'Right' */
	CENTER,					/* Apple calls this 'Center' */
	FRONT_LEFT,
	FRONT_RIGHT,
	FRONT_CENTER,
	REAR_CENTER,				/* Apple calls this 'Center Surround', Msft calls this 'Back Center' */
	REAR_LEFT,				/* Apple calls this 'Left Surround', Msft calls this 'Back Left' */
	REAR_RIGHT,				/* Apple calls this 'Right Surround', Msft calls this 'Back Right' */
	LFE,						/* Apple calls this 'LFEScreen', Msft calls this 'Low Frequency'  */
	FRONT_LEFT_OF_CENTER,	/* Apple calls this 'Left Center' */
	FRONT_RIGHT_OF_CENTER,	/* Apple calls this 'Right Center */
	SIDE_LEFT,				/* Apple calls this 'Left Surround Direct' */
	SIDE_RIGHT,				/* Apple calls this 'Right Surround Direct' */
	TOP_CENTER,				/* Apple calls this 'Top Center Surround' */
	TOP_FRONT_LEFT,			/* Apple calls this 'Vertical Height Left' */
	TOP_FRONT_RIGHT,			/* Apple calls this 'Vertical Height Right' */
	TOP_FRONT_CENTER,		/* Apple calls this 'Vertical Height Center' */
	TOP_REAR_LEFT,			/* Apple and MS call this 'Top Back Left' */
	TOP_REAR_RIGHT,			/* Apple and MS call this 'Top Back Right' */
	TOP_REAR_CENTER,			/* Apple and MS call this 'Top Back Center' */

	AMBISONIC_B_W,
	AMBISONIC_B_X,
	AMBISONIC_B_Y,
	AMBISONIC_B_Z,
}

MODE_READ :: 0x10
MODE_WRITE :: 0x20
MODE_RDWR :: 0x30

Seek_Whence :: enum c.int {
	SEEK_SET = libc.SEEK_SET,
	SEEK_CUR = libc.SEEK_CUR,
	SEEK_END = libc.SEEK_END,
}

count_t :: c.int64_t

Info :: struct {
	frames: count_t,
	samplerate: c.int,
	channels: c.int,
	format: c.int,
	sections: c.int,
	seekable: c.int,
}

Stream :: distinct rawptr

@(link_prefix="sf_")
foreign sndfile {
	open :: proc(path: cstring, mode: c.int, info: ^Info) -> Stream ---
	wchar_open :: proc(path: [^]u16, mode: c.int, info: ^Info) -> Stream ---
	close :: proc(stream: Stream) -> c.int ---
	seek :: proc(stream: Stream, frames: count_t, whence: Seek_Whence) -> count_t ---
	readf_float :: proc(stream: Stream, buffer: [^]f32, frames: count_t) -> count_t ---
}

