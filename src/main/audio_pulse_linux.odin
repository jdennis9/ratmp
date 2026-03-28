#+private file
package main

import "core:fmt"
import "core:thread"
import "core:sync"
import "base:runtime"

import "core:log"
import "core:c"
import pa "src:bindings/pulse"

CHANNELS :: 2
SAMPLERATE :: 48000

_Stream_Error :: enum {
	None,
	ConnectionFailed,
	CreateStreamFailed,
}

_Stream_Message :: enum {
	DropBuffer,
	Pause,
	Resume,
	Quit,
}

_stream: struct {
	ctx: runtime.Context,
	pa_context: ^pa.context_,
	stream: ^pa.stream,
	mainloop: ^pa.mainloop,
	mainloop_api: ^pa.mainloop_api,
	ready_sem: sync.Sema,
	error: _Stream_Error,
	session_thread: ^thread.Thread,
	messages: bit_set[_Stream_Message],
	volume: f32,
	index: u32,
	callback: Audio_Callback,
	callback_data: rawptr,
	paused: bool,
}

@private
use_audio_pulse :: proc() {

	_audio_impl_init = proc(cb: Audio_Callback, cb_data: rawptr) -> bool {
		s := &_stream
		defer if s.error != .None {
			_audio_impl_shutdown()
		}

		s.ctx = context
		s.callback = cb
		s.callback_data = cb_data

		s.mainloop = pa.mainloop_new()
		s.mainloop_api = pa.mainloop_get_api(s.mainloop)
		s.pa_context = pa.context_new(s.mainloop_api, "RAT MP")
		s.session_thread = thread.create(_stream_session_thread)
		s.session_thread.data = s
		_check(pa.context_connect(s.pa_context, nil, 0, nil)) or_return
		pa.context_set_state_callback(s.pa_context, _context_state_proc, s)

		thread.start(s.session_thread)

		sync.sema_wait(&s.ready_sem)

		return s.error == .None
	}

	_audio_impl_shutdown = proc() {
		s := &_stream

		_send_message(.Quit)
		thread.join(s.session_thread)

		pa.stream_unref(s.stream)
		pa.context_unref(s.pa_context)
		pa.mainloop_free(s.mainloop)
		thread.destroy(s.session_thread)

		free(s)
	}

	_audio_impl_drop_buffer = proc() {
		_send_message(.DropBuffer)
	}

	_audio_impl_pause = proc() -> bool {
		_send_message(.Pause)
		return true
	}

	_audio_impl_resume = proc() -> bool {
		_send_message(.Resume)
		return true
	}

	_audio_impl_is_paused = proc() -> bool {
		return _stream.paused
	}

	_audio_impl_set_volume = proc(v: f32) {
		s := &_stream
		cv: pa.cvolume
		index := pa.stream_get_index(s.stream)

		pa.cvolume_set(&cv, CHANNELS, cast(pa.volume_t) (pa.VOLUME_NORM * v))
		pa.context_set_sink_input_volume(s.pa_context, index, &cv, nil, nil)
		s.volume = v
	}

	_audio_impl_get_volume = proc() -> f32 {
		return _stream.volume
	}

	_audio_impl_start = proc() -> bool {
		return true
	}

	_audio_impl_stop = proc() {
	}
}

_check :: proc(error: i32, expr := #caller_expression) -> bool {
	if error != 0 {
		log.error(expr, ": ", pa.strerror(error), sep="")
		return false
	}
	return true
}

_stream_write_callback :: proc "c" (stream: ^pa.stream, length: c.size_t, userdata: rawptr) {
	s := &_stream
	context = s.ctx

	nbytes := length
	out_ptr: rawptr
	out_buf: []f32

	if !_check(pa.stream_begin_write(stream, &out_ptr, &nbytes)) {return}

	assert(nbytes % size_of(f32) == 0)

	out_buf = (cast([^]f32) out_ptr)[:nbytes/size_of(f32)]
	for &f in out_buf do f = 0

	status := s.callback(s.callback_data, .Stream, out_buf, Audio_Spec{
		channels = CHANNELS, samplerate = SAMPLERATE
	})

	if status == .Finish {
		s.callback(s.callback_data, .TrackFinised, nil, {})
	}

	// Clip output
	for &f in out_buf {
		f = clamp(f, -1, 1)
	}

	pa.stream_write(stream, out_ptr, nbytes, nil, 0, .RELATIVE)
}

_send_message :: proc(message: _Stream_Message) {
	s := &_stream
	b := sync.atomic_load(&s.messages)
	b |= {message}
	sync.atomic_store(&s.messages, b)
	pa.mainloop_wakeup(s.mainloop)
}

_stream_session_thread :: proc(t: ^thread.Thread) {
	s := &_stream
	context = s.ctx
	
	for {
		pa.mainloop_iterate(s.mainloop, true, nil)

		messages := sync.atomic_load(&s.messages)
		defer sync.atomic_store(&s.messages, {})

		if messages != {} do log.debug(messages)

		if .DropBuffer in messages {
			pa.stream_flush(s.stream, nil, nil)
			s.callback(s.callback_data, .BufferDropped, nil, {})
		}

		if .Pause in messages {
			pa.stream_cork(s.stream, 1, nil, nil)
			s.callback(s.callback_data, .Paused, nil, {})
			s.paused = true
		}

		if .Resume in messages {
			pa.stream_cork(s.stream, 0, nil, nil)
			s.callback(s.callback_data, .Resumed, nil, {})
			s.paused = false
		}

		if .Quit in messages {
			break
		}
	}

	pa.mainloop_quit(s.mainloop, 0)
}

_stream_state_callback :: proc "c" (stream: ^pa.stream, userdata: rawptr) {
	s := &_stream
	context = s.ctx

	state := pa.stream_get_state(stream)
	
	#partial switch state {
		case .READY: {
			index := pa.stream_get_index(stream)
			pa.stream_set_write_callback(s.stream, _stream_write_callback, s)
			pa.context_get_sink_input_info(s.pa_context, index, _stream_info_callback, s)
			pa.context_subscribe(s.pa_context, pa.SUBSCRIPTION_MASK_SINK_INPUT)
			pa.context_set_subscribe_callback(s.pa_context, _context_subscribe_callback, s)
			sync.sema_post(&s.ready_sem)
			return
		}
	}
}

_stream_info_callback :: proc "c" (ctx: ^pa.context_, i: ^pa.sink_input_info, eol: c.int, userdata: rawptr) {
	s := &_stream

	if i == nil {return}

	if i.has_volume != 0 {
		s.volume = f32(pa.cvolume_avg(&i.volume)) / pa.VOLUME_NORM
	}
	else {
		s.volume = 1
	}
}

_context_subscribe_callback :: proc "c" (
	ctx: ^pa.context_, t: pa.subscription_event_type_t, idx: u32, userdata: rawptr
) {
	s := &_stream

	if idx != pa.stream_get_index(s.stream) do return

	pa.context_get_sink_input_info(ctx, idx, _stream_info_callback, s)
}

_begin_stream_session :: proc() -> (ok: bool) {
	s := &_stream
	sample_spec := pa.sample_spec {
		channels = CHANNELS,
		rate = SAMPLERATE,
		format =.FLOAT32LE,
	}
	
	defer if !ok {
		sync.sema_post(&s.ready_sem)
	}

	s.stream = pa.stream_new(s.pa_context, PROGRAM_NAME, &sample_spec, nil)
	if s.stream == nil do return
	_check(pa.stream_connect_playback(s.stream, nil, nil, 0, nil, nil)) or_return
	pa.stream_set_state_callback(s.stream, _stream_state_callback, s)

	sync.sema_post(&s.ready_sem)

	return true
}

_context_state_proc :: proc "c" (pa_ctx: ^pa.context_, userdata: rawptr) {
	s := &_stream
	context = s.ctx

	state := pa.context_get_state(pa_ctx)

	log.debug("Context state:", state)

	#partial switch state {
		case .READY: {
			s.error = _begin_stream_session() ? .None : .CreateStreamFailed
			return
		}
		case .FAILED: {
			s.error = .ConnectionFailed
			sync.sema_post(&s.ready_sem)
		}
	}

}
