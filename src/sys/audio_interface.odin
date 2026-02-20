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
package sys

import "core:log"

Audio_Event :: enum {
	Pause,
	Resume,
	DropBuffer,
	Finish,
	DeviceLost,
}

Audio_Callback_Status :: enum {
	Continue,
	Finish,
}

Audio_Event_Callback :: #type proc(data: rawptr, event: Audio_Event)
Audio_Stream_Callback :: #type proc(data: rawptr, buffer: []f32, channels, samplerate: i32) -> Audio_Callback_Status

Audio_Stream :: struct {
	config: Audio_Stream_Config,
	channels, samplerate: i32,
}

Audio_Device_ID :: distinct uintptr

Audio_Device :: struct {
	name: [120]u8,
	id: Audio_Device_ID,
}

Audio_Stream_Config :: struct {
	// 0 for default
	device_id: Audio_Device_ID,
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	callback_data: rawptr,
}

Audio_Backend :: enum {
	PortAudio,
	Pulse,
	Wasapi,
}

audio_use_backend :: proc(backend: Audio_Backend) {
	when ODIN_OS == .Linux {
		#partial switch backend {
			case .PortAudio:
				audio_use_portaudio_backend()
			case .Pulse:
				audio_use_pulse_backend()
			case: log.error("Backend", backend, "not supported on this platform")
		}
	}
	else when ODIN_OS == .Windows {
		#partial switch backend {
			case .Wasapi:
				audio_use_wasapi_backend()
			case: log.error("Backend", backend, "not supported on this platform")
		}
	}
}

audio_init :: proc() -> bool {
	if _audio_impl_init == nil {
		log.error("No audio backend selected")
		return false
	}

	return _audio_impl_init()
}

audio_shutdown :: proc() {
	_audio_impl_shutdown()
}

audio_create_stream :: proc(config: Audio_Stream_Config) -> (stream: ^Audio_Stream, ok: bool) {
	stream = _audio_impl_create_stream(config) or_return
	stream.config = config
	return stream, true
}

audio_destroy_stream :: proc(stream: ^Audio_Stream) {
	if stream == nil {return}
	_audio_impl_destroy_stream(stream)
}

audio_stream_set_volume :: proc(stream: ^Audio_Stream, volume: f32) {
	if stream == nil {return}
	_audio_impl_stream_set_volume(stream, volume)
}

audio_stream_get_volume :: proc(stream: ^Audio_Stream) -> f32 {
	if stream == nil {return 0}
	return _audio_impl_stream_get_volume(stream)
}

audio_stream_drop_buffer :: proc(stream: ^Audio_Stream) {
	if stream == nil {return}
	_audio_impl_stream_drop_buffer(stream)
}

audio_stream_pause :: proc(stream: ^Audio_Stream) {
	if stream == nil {return}
	_audio_impl_stream_pause(stream)
}

audio_stream_resume :: proc(stream: ^Audio_Stream) {
	if stream == nil {return}
	_audio_impl_stream_resume(stream)
}

