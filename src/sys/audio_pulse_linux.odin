/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
#+private file
package sys

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

_Pulse_Stream :: struct {
	using base: Audio_Stream,
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

_check :: proc(error: c.int, expr := #caller_expression) -> bool {
	if error != 0 {
		log.error(expr, ": ", pa.strerror(error), sep="")
		return false
	}
	return true
}

_stream_write_callback :: proc "c" (stream: ^pa.stream, length: c.size_t, userdata: rawptr) {
	s := cast(^_Pulse_Stream) userdata
	context = s.ctx

	nbytes := length
	out_ptr: rawptr
	out_buf: []f32

	if !_check(pa.stream_begin_write(stream, &out_ptr, &nbytes)) {return}

	out_buf = (cast([^]f32) out_ptr)[:nbytes/size_of(f32)]
	for &f in out_buf {f = 0}

	status := s.config.stream_callback(s.config.callback_data, out_buf, CHANNELS, SAMPLERATE)

	if status == .Finish && s.config.event_callback != nil {
		s.config.event_callback(s.config.callback_data, .Finish)
	}

	pa.stream_write(stream, out_ptr, nbytes, nil, 0, .RELATIVE)
}

_send_message :: proc(s: ^_Pulse_Stream, message: _Stream_Message) {
	b := sync.atomic_load(&s.messages)
	b |= {message}
	sync.atomic_store(&s.messages, b)
	pa.mainloop_wakeup(s.mainloop)
}

_stream_session_thread :: proc(t: ^thread.Thread) {
	s := cast(^_Pulse_Stream) t.data
	context = s.ctx
	
	for {
		pa.mainloop_iterate(s.mainloop, true, nil)

		messages := sync.atomic_load(&s.messages)
		defer sync.atomic_store(&s.messages, {})

		if .DropBuffer in messages {
			pa.stream_flush(s.stream, nil, nil)
			if s.config.event_callback != nil {
				s.config.event_callback(s.config.callback_data, .DropBuffer)
			}
		}

		if .Pause in messages {
			pa.stream_cork(s.stream, 1, nil, nil)
			if s.config.event_callback != nil {
				s.config.event_callback(s.config.callback_data, .Pause)
			}
		}

		if .Resume in messages {
			pa.stream_cork(s.stream, 0, nil, nil)
			if s.config.event_callback != nil {
				s.config.event_callback(s.config.callback_data, .Resume)
			}
		}

		if .Quit in messages {
			break
		}
	}

	pa.mainloop_quit(s.mainloop, 0)
}

_stream_state_callback :: proc "c" (stream: ^pa.stream, userdata: rawptr) {
	s := cast(^_Pulse_Stream) userdata
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
	s := cast(^_Pulse_Stream) userdata

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
	s := cast(^_Pulse_Stream) userdata

	if idx != pa.stream_get_index(s.stream) {return}

	pa.context_get_sink_input_info(ctx, idx, _stream_info_callback, s)
}

_begin_stream_session :: proc(s: ^_Pulse_Stream) -> (ok: bool) {
	sample_spec := pa.sample_spec {
		channels = 2,
		rate = 48000,
		format =.FLOAT32LE,
	}
	
	defer if !ok {
		sync.sema_post(&s.ready_sem)
	}

	s.stream = pa.stream_new(s.pa_context, "RAT MP Playback", &sample_spec, nil)
	if s.stream == nil {return}
	_check(pa.stream_connect_playback(s.stream, nil, nil, 0, nil, nil)) or_return
	pa.stream_set_state_callback(s.stream, _stream_state_callback, s)

	sync.sema_post(&s.ready_sem)

	return true
}

_context_state_proc :: proc "c" (pa_ctx: ^pa.context_, userdata: rawptr) {
	s := cast(^_Pulse_Stream) userdata
	context = s.ctx

	state := pa.context_get_state(pa_ctx)

	log.debug("Context state:", state)

	#partial switch state {
		case .READY: {
			s.error = _begin_stream_session(s) ? .None : .CreateStreamFailed
			return
		}
		case .FAILED: {
			s.error = .ConnectionFailed
			sync.sema_post(&s.ready_sem)
		}
	}

}

_init :: proc() -> bool {
	return true
}

_shutdown :: proc() {
}

_create_stream :: proc(
	config: Audio_Stream_Config,
) -> (handle: ^Audio_Stream, ok: bool) {
	s := new(_Pulse_Stream)
	defer if !ok {
		_destroy_stream(s)
	}

	s.samplerate = SAMPLERATE
	s.channels = CHANNELS
	s.ctx = context

	s.mainloop = pa.mainloop_new()
	s.mainloop_api = pa.mainloop_get_api(s.mainloop)
	s.pa_context = pa.context_new(s.mainloop_api, "RAT MP")
	s.session_thread = thread.create(_stream_session_thread)
	s.session_thread.data = s
	_check(pa.context_connect(s.pa_context, nil, 0, nil)) or_return
	pa.context_set_state_callback(s.pa_context, _context_state_proc, s)

	thread.start(s.session_thread)

	sync.sema_wait(&s.ready_sem)

	return s, s.error == .None
}

_stream_drop_buffer :: proc(stream: ^Audio_Stream) {
	s := cast(^_Pulse_Stream) stream
	_send_message(s, .DropBuffer)
}

_stream_pause :: proc(stream: ^Audio_Stream) {
	s := cast(^_Pulse_Stream) stream
	_send_message(s, .Pause)
}

_stream_resume :: proc(stream: ^Audio_Stream) {
	s := cast(^_Pulse_Stream) stream
	_send_message(s, .Resume)
}

_stream_set_volume :: proc(stream: ^Audio_Stream, volume: f32) {
	s := cast(^_Pulse_Stream) stream
	cv: pa.cvolume
	index := pa.stream_get_index(s.stream)

	pa.cvolume_set(&cv, CHANNELS, cast(pa.volume_t) (pa.VOLUME_NORM * volume))
	pa.context_set_sink_input_volume(s.pa_context, index, &cv, nil, nil)
	s.volume = volume
}

_stream_get_volume :: proc(stream: ^Audio_Stream) -> (volume: f32) {
	s := cast(^_Pulse_Stream) stream
	index := pa.stream_get_index(s.stream)
	return s.volume
}

_destroy_stream :: proc(stream: ^Audio_Stream) {
	s := cast(^_Pulse_Stream) stream

	_send_message(s, .Quit)
	thread.join(s.session_thread)

	pa.stream_unref(s.stream)
	pa.context_unref(s.pa_context)
	pa.mainloop_free(s.mainloop)
	thread.destroy(s.session_thread)

	free(s)
}
