#+private file
package sys

import "core:c"
import "core:log"
import "base:runtime"

import "core:thread"
import "core:sync"
import "core:time"

import pa "src:bindings/pulse"

SAMPLERATE :: 48000
BUFFER_DURATION :: 1000
CHANNELS :: 2
BUFFER_SAMPLES :: SAMPLERATE * CHANNELS

_Message :: enum {
	DropBuffer,
	Terminate,
}

_Pulse_Stream :: struct {
	using base: Audio_Stream,

	stream: ^pa.stream,
	mainloop: ^pa.threaded_mainloop,
	mainloop_api: ^pa.mainloop_api,
	pa_context: ^pa.context_,
	is_active, is_stopped: b32,

	volume: f32,

	ctx: runtime.Context,
}

@private
audio_use_pulse_backend :: proc() {
	_audio_impl_init = _init
	_audio_impl_shutdown = _shutdown
	_audio_impl_create_stream = _create_stream
	_audio_impl_destroy_stream = _destroy_stream
	_audio_impl_stream_drop_buffer = _stream_drop_buffer
	_audio_impl_stream_set_volume = _stream_set_volume
	_audio_impl_stream_get_volume = _stream_get_volume
	_audio_impl_stream_pause = _stream_pause
	_audio_impl_stream_resume = _stream_resume
}

_init :: proc() -> bool {
	return true
}

_shutdown :: proc() {
}

_write_callback :: proc "c" (stream: ^pa.stream, length: c.size_t, userdata: rawptr) {
	s := cast(^_Pulse_Stream) userdata
	context = s.ctx
	nbytes := length
	out_ptr: rawptr
	out_buf: []f32

	if !_check(pa.stream_begin_write(stream, &out_ptr, &nbytes)) {return}

	out_buf = (cast([^]f32) out_ptr)[:nbytes/size_of(f32)]
	for &f in out_buf {f = 0}

	s.config.stream_callback(s.config.callback_data, out_buf, CHANNELS, SAMPLERATE)

	pa.stream_write(stream, out_ptr, nbytes, nil, 0, .RELATIVE)

	pa.threaded_mainloop_signal(s.mainloop, false)
}

_drop_buffer_callback :: proc "c" (api: ^pa.mainloop_api, userdata: rawptr) {
	s := cast(^_Pulse_Stream) userdata
	context = s.ctx

	if s.config.event_callback != nil {
		s.config.event_callback(s.config.callback_data, .DropBuffer)
	}
}

_check :: proc(code: c.int, expr := #caller_expression) -> bool {
	if code != 0 {
		log.error(expr, pa.strerror(code))
		return false
	}

	return true
}

_create_stream :: proc(
	config: Audio_Stream_Config,
) -> (handle: ^Audio_Stream, ok: bool) {
	stream := new(_Pulse_Stream)
	defer if !ok {free(stream)}

	stream.samplerate = SAMPLERATE
	stream.channels = CHANNELS
	stream.ctx = context
	stream.volume = 1

	ss := pa.sample_spec {
		channels = CHANNELS,
		format = .FLOAT32LE,
		rate = SAMPLERATE,
	}

	stream.mainloop = pa.threaded_mainloop_new()
	defer if !ok {pa.threaded_mainloop_free(stream.mainloop)}
	_check(pa.threaded_mainloop_start(stream.mainloop))
	
	stream.mainloop_api = pa.threaded_mainloop_get_api(stream.mainloop)
	stream.pa_context = pa.context_new(pa.threaded_mainloop_get_api(stream.mainloop), "RAT MP")
	_check(pa.context_connect(stream.pa_context, nil, 0, nil))
	
	for pa.context_get_state(stream.pa_context) != .READY {}

	stream.stream = pa.stream_new(
		stream.pa_context,
		"RAT MP",
		&ss, nil,
	)
	
	if stream.stream == nil {return}
	defer if !ok {pa.stream_unref(stream.stream); stream.stream = nil}
	
	_check(pa.stream_connect_playback(stream.stream, nil, nil, 0, nil, nil)) or_return
	pa.stream_set_write_callback(stream.stream, _write_callback, stream)

	return stream, true
}

_destroy_stream :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Pulse_Stream) handle
	
	pa.context_disconnect(stream.pa_context)
	pa.context_unref(stream.pa_context)
	
	pa.stream_unref(stream.stream)

	pa.threaded_mainloop_stop(stream.mainloop)
	pa.threaded_mainloop_free(stream.mainloop)

	free(stream)
}

_stream_drop_buffer :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Pulse_Stream) handle

	if stream.stream == nil {return}
	pa.threaded_mainloop_lock(stream.mainloop)
	pa.stream_flush(stream.stream, nil, nil)
	pa.mainloop_api_once(stream.mainloop_api, _drop_buffer_callback, stream)
	pa.threaded_mainloop_unlock(stream.mainloop)
}

_stream_pause :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Pulse_Stream) handle

	if stream.stream == nil {return}

	if stream.config.event_callback != nil {
		stream.config.event_callback(stream.config.callback_data, .Pause)
	}
}

_stream_resume :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Pulse_Stream) handle

	if stream.stream == nil {return}

	if stream.config.event_callback != nil {
		stream.config.event_callback(stream.config.callback_data, .Resume)
	}
}

_stream_set_volume :: proc(handle: ^Audio_Stream, volume: f32) {
	stream := cast(^_Pulse_Stream) handle
	stream.volume = volume
}

_stream_get_volume :: proc(handle: ^Audio_Stream) -> (volume: f32) {
	stream := cast(^_Pulse_Stream) handle
	return stream.volume
}

