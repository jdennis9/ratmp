/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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

import "base:runtime"

import "core:log"
import "core:c"
import pa "src:bindings/portaudio"

_Portaudio_Stream :: struct {
	using base: Audio_Stream,
	stream: pa.Stream,
	volume: f32,
	ctx: runtime.Context,
}

@private
audio_use_portaudio_backend :: proc() {
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

_callback_wrapper :: proc "c" (
	input, output: rawptr,
    frame_count: c.ulong,
    time_info: ^pa.StreamCallbackTimeInfo,
    status_flags: pa.StreamCallbackFlags,
    user_data: rawptr,
) -> pa.StreamCallbackResult {
	stream := cast(^_Portaudio_Stream) user_data
	config := stream.config

	context = stream.ctx
	output_buf: []f32 = (cast([^]f32)output)[:frame_count*2]

	status := config.stream_callback(config.callback_data, output_buf, 2, 48000)
	if status == .Finish {
		config.event_callback(config.callback_data, .Finish)
	}

	for &f in output_buf {
		f *= stream.volume
	}

	return .Continue
}

_check :: proc(code: pa.ErrorCode, expr := #caller_expression) -> bool {
	if code == .NoError {return true}
	log.error(expr, ": ", code, sep="")
	return false
}

_init :: proc() -> bool {
	if pa.Initialize() != .NoError {
		return false
	}

	return true
}

_shutdown :: proc() {
	pa.Terminate()
}

_create_stream :: proc(
	config: Audio_Stream_Config,
) -> (handle: ^Audio_Stream, ok: bool) {
	stream := new(_Portaudio_Stream)
	defer if !ok {free(stream)}

	stream.samplerate = 48000
	stream.channels = 2
	stream.ctx = context
	stream.volume = 1

	_check(pa.OpenDefaultStream(
		&stream.stream, 0, 2, pa.SampleFormat_Float32, 48000, 24000,
		_callback_wrapper, stream
	)) or_return
	_check(pa.StartStream(stream.stream)) or_return

	return stream, true
}

_stream_drop_buffer :: proc(handle: ^Audio_Stream) {
	log.warn("drop_buffer unsupported by PortAudio backend")
}

_stream_pause :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Portaudio_Stream) handle

	if stream.stream == nil {return}

	if stream.config.event_callback != nil {
		stream.config.event_callback(stream.config.callback_data, .Pause)
	}

	pa.StopStream(stream.stream)
}

_stream_resume :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Portaudio_Stream) handle

	if stream.stream == nil {return}

	if stream.config.event_callback != nil {
		stream.config.event_callback(stream.config.callback_data, .Resume)
	}

	pa.StartStream(stream.stream)
}

_stream_set_volume :: proc(handle: ^Audio_Stream, volume: f32) {
	stream := cast(^_Portaudio_Stream) handle
	stream.volume = volume
}

_stream_get_volume :: proc(handle: ^Audio_Stream) -> (volume: f32) {
	stream := cast(^_Portaudio_Stream) handle
	return stream.volume
}

_destroy_stream :: proc(handle: ^Audio_Stream) {
	stream := cast(^_Portaudio_Stream) handle
	if stream.stream == nil {return}
	pa.CloseStream(stream.stream)
}
