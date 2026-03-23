package pulse

import "core:c"

foreign import lib "system:pulse"

CHANNELS_MAX :: 32

context_ :: struct {}
threaded_mainloop :: struct {}
mainloop :: struct {}
mainloop_api :: struct {}
stream :: struct {}
operation :: struct {}
spawn_api :: struct {}

context_flags_t :: c.int
volume_t :: u32
stream_flags_t :: c.int
usec_t :: u64

VOLUME_NORM :: 0x10000
VOLUME_MUTED :: 0
VOLUME_MAX :: max(u32)/2

sample_format_t :: enum c.int {
	U8,
	ALAW,
	ULAW,
	S16LE,
	S16BE,
	FLOAT32LE,
	FLOAT32BE,
	S32LE,
	S32BE,
	S24LE,
	S24BE,
	S24_32LE,
	S24_32BE,
}

channel_position_t :: enum c.int {
	INVAL,
	MONO,
	FRONT_LEFT,
	FRONT_RIGHT,
	FRONT_CENTER,
	REAR_CENTER,
	REAR_LEFT,
	REAR_RIGHT,
	LFE,
	FRONT_LEFT_OF_CENTER,
	FRONT_RIGHT_OF_CENTER,
	SIDE_LEFT,
	SIDE_RIGHT,
	AUX0,
	AUX1,
	AUX2,
	AUX3,
	AUX4,
	AUX5,
	AUX6,
	AUX7,
	AUX8,
	AUX9,
	AUX10,
	AUX11,
	AUX12,
	AUX13,
	AUX14,
	AUX15,
	AUX16,
	AUX17,
	AUX18,
	AUX19,
	AUX20,
	AUX21,
	AUX22,
	AUX23,
	AUX24,
	AUX25,
	AUX26,
	AUX27,
	AUX28,
	AUX29,
	AUX30,
	AUX31,
	TOP_CENTER,
	TOP_FRONT_LEFT,
	TOP_FRONT_RIGHT,
	TOP_FRONT_CENTER,
	TOP_REAR_LEFT,
	TOP_REAR_RIGHT,
	TOP_REAR_CENTER,
}

subscription_mask_t :: c.int
SUBSCRIPTION_MASK_NULL :: 0x0000
SUBSCRIPTION_MASK_SINK :: 0x0001
SUBSCRIPTION_MASK_SOURCE :: 0x0002
SUBSCRIPTION_MASK_SINK_INPUT :: 0x0004
SUBSCRIPTION_MASK_SOURCE_OUTPUT :: 0x0008
SUBSCRIPTION_MASK_MODULE :: 0x0010
SUBSCRIPTION_MASK_CLIENT :: 0x0020
SUBSCRIPTION_MASK_SAMPLE_CACHE :: 0x0040
SUBSCRIPTION_MASK_SERVER :: 0x0080
SUBSCRIPTION_MASK_AUTOLOAD :: 0x0100
SUBSCRIPTION_MASK_CARD :: 0x0200
SUBSCRIPTION_MASK_ALL::  0x02ff

subscription_event_type_t :: enum c.int {
	SINK = 0x0000,
	SOURCE = 0x0001,
	SINK_INPUT = 0x0002,
	SOURCE_OUTPUT = 0x0003,
	MODULE = 0x0004,
	CLIENT = 0x0005,
	SAMPLE_CACHE = 0x0006,
	SERVER = 0x0007,
	AUTOLOAD = 0x0008,
	CARD = 0x0009,
	FACILITY_MASK = 0x000F,
	NEW = 0x0000,
	CHANGE = 0x0010,
	REMOVE = 0x0020,
}

seek_mode_t :: enum c.int {
	RELATIVE,
	ABSOLUTE,
	RELATIVE_ON_READ,
	RELATIVE_END,
}

context_state_t :: enum c.int {
	UNCONNECTED,
	CONNECTING,
	AUTHORIZING,
	SETTING_NAME,
	READY,
	FAILED,
	TERMINATED,
}

stream_state_t :: enum c.int {
	UNCONNECTED,
	CREATING,
	READY,
	FAILED,
	TERMINATED,
}

sample_spec :: struct {
	format: sample_format_t,
	rate: u32,
	channels: u8,
}

channel_map :: struct {
	channels: u8,
	map_: [CHANNELS_MAX]channel_position_t
}

buffer_attr :: struct {
	maxlength: u32,
	tlength: u32,
	prebuf: u32,
	minreq: u32,
	fragsize: u32,
}


cvolume :: struct {
	channels: u8,
	values: [CHANNELS_MAX]volume_t,
}

sink_input_info :: struct {
	index: u32,
	name: cstring,
	owner_module: u32,
	client: u32,
	sink: u32,
	sample_spec: sample_spec,
	channel_map: channel_map,
	volume: cvolume,
	buffer_usec: usec_t,
	sink_usec: usec_t,
	resample_method: cstring,
	driver: cstring,
	mute: c.int,
	proplist: rawptr,
	corked: c.int,
	has_volume: c.int,
	volume_writable: c.int,
}

stream_success_cb_t :: #type proc "c" (s: ^stream, success: c.int, userdata: rawptr)
stream_request_cb_t :: #type proc "c" (s: ^stream, nbytes: c.size_t, userdata: rawptr)
stream_notify_cb_t :: #type proc "c" (s: ^stream, userdata: rawptr)
context_notify_cb_t :: #type proc "c" (c: ^context_, userdata: rawptr)
sink_input_info_cb_t :: #type proc "c" (ctx: ^context_, i: ^sink_input_info, eol: c.int, userdata: rawptr)
context_subscribe_cb_t :: #type proc "c" (ctx: ^context_, event_type: subscription_event_type_t, idx: u32, userdata: rawptr)

@(link_prefix="pa_")
foreign lib {
	strerror :: proc(error: c.int) -> cstring ---

	threaded_mainloop_new :: proc() -> ^threaded_mainloop ---
	threaded_mainloop_free :: proc(m: ^threaded_mainloop) ---
	threaded_mainloop_start :: proc(m: ^threaded_mainloop) -> c.int ---
	threaded_mainloop_stop :: proc(m: ^threaded_mainloop) ---
	threaded_mainloop_lock :: proc(m: ^threaded_mainloop) ---
	threaded_mainloop_unlock :: proc(m: ^threaded_mainloop) ---
	threaded_mainloop_wait :: proc(m: ^threaded_mainloop) ---
	threaded_mainloop_signal :: proc(m: ^threaded_mainloop, wait_for_accept: b32) ---
	threaded_mainloop_get_api :: proc(m: ^threaded_mainloop) -> ^mainloop_api ---

	mainloop_api_once :: proc(m: ^mainloop_api, callback: proc(m: ^mainloop_api, userdata: rawptr), userdata: rawptr) ---

	mainloop_new :: proc() -> ^mainloop ---
	mainloop_free :: proc(m: ^mainloop) ---
	mainloop_iterate :: proc(m: ^mainloop, blocking: b32, retval: ^c.int) -> c.int ---
	mainloop_wakeup :: proc(m: ^mainloop) ---
	mainloop_prepare :: proc(m: ^mainloop, timeout: c.int) -> c.int ---
	mainloop_poll :: proc(m: ^mainloop) -> c.int ---
	mainloop_dispatch :: proc(m: ^mainloop) -> c.int ---
	mainloop_run :: proc(m: ^mainloop, retval: ^c.int) -> c.int ---
	mainloop_quit :: proc(m: ^mainloop, retval: c.int) ---
	mainloop_get_api :: proc(m: ^mainloop) -> ^mainloop_api ---

	context_new :: proc(m: ^mainloop_api, name: cstring) -> ^context_ ---
	context_unref :: proc(c: ^context_) ---
	context_ref :: proc(c: ^context_) -> ^context_ ---
	context_connect :: proc(
		ctx: ^context_,
		server: cstring,
		flags: context_flags_t,
		spawn_api: ^spawn_api,
	) -> c.int ---
	context_disconnect :: proc(c: ^context_) ---
	context_get_state :: proc(c: ^context_) -> context_state_t ---
	context_set_state_callback :: proc(c: ^context_, cb: context_notify_cb_t, userdata: rawptr) ---

	stream_new :: proc(
		ctx: ^context_, name: cstring, ss: ^sample_spec, ch_map: ^channel_map
	) -> ^stream ---
	stream_unref :: proc(s: ^stream) ---
	stream_ref :: proc(s: ^stream) -> ^stream ---
	stream_get_state :: proc(s: ^stream) -> stream_state_t ---
	stream_get_index :: proc(s: ^stream) -> u32 ---
	stream_get_device_index :: proc(s: ^stream) -> u32 ---
	stream_get_device_name :: proc(s: ^stream) -> cstring ---
	stream_is_suspended :: proc(s: ^stream) -> b32 ---
	stream_is_corked :: proc(s: ^stream) -> b32 ---
	stream_connect_playback :: proc(
		s: ^stream,
		device_name: cstring, // optional
		attr: ^buffer_attr, // optional
		flags: stream_flags_t, // optional
		volume: ^cvolume, // optional
		sync_stream: ^stream, // optional
	) -> c.int ---
	stream_cork :: proc(
		s: ^stream, paused: c.int, cb: stream_success_cb_t, userdata: rawptr,
	) -> ^operation ---
	stream_drain :: proc(
		s: ^stream, cb: stream_success_cb_t, userdata: rawptr
	) -> ^operation ---
	stream_flush :: proc(s: ^stream, cb: stream_success_cb_t, userdata: rawptr) -> c.int ---
	stream_disconnect :: proc(s: ^stream) -> c.int ---

	stream_set_write_callback :: proc(s: ^stream, cb: stream_request_cb_t, userdata: rawptr) ---
	stream_set_state_callback :: proc(s: ^stream, cb: stream_notify_cb_t, userdata: rawptr) ---
	stream_set_started_callback :: proc(s: ^stream, cb: stream_notify_cb_t, userdata: rawptr) ---
	stream_set_underflow_callback :: proc(s: ^stream, cb: stream_notify_cb_t, userdata: rawptr) ---

	stream_begin_write :: proc(
		s: ^stream, data: ^rawptr, nbytes: ^c.size_t,
	) -> c.int ---
	stream_write :: proc(
		s: ^stream, data: rawptr, nbytes: c.size_t,
		free_cb: rawptr, offset: i64, seek: seek_mode_t,
	) -> c.int ---

	cvolume_init :: proc(a: ^cvolume) -> ^cvolume ---
	cvolume_set :: proc(a: ^cvolume, channels: c.uint, v: volume_t) -> ^cvolume ---
	cvolume_avg :: proc(a: ^cvolume) -> volume_t ---

	context_set_sink_input_volume :: proc(
		ctx: ^context_, idx: u32, v: ^cvolume, cb: rawptr = nil, userdata: rawptr = nil
	) -> ^operation ---

	context_get_sink_input_info :: proc(
		ctx: ^context_, idx: u32, cb: sink_input_info_cb_t, userdata: rawptr
	) -> ^operation ---

	context_subscribe :: proc(
		ctx: ^context_,
		mask: subscription_mask_t,
		cb: rawptr = nil,
		userdata: rawptr = nil,
	) -> ^operation ---

	context_set_subscribe_callback :: proc(
		ctx: ^context_,
		cb: context_subscribe_cb_t,
		userdata: rawptr,
	) ---
}
