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
package sys

import "base:runtime"

import "core:log"
import "core:c"
import "core:time"
import pa "src:bindings/portaudio"

Audio_Stream :: struct {
	using common: Audio_Stream_Common,
	stream: pa.Stream,
	volume: f32,
	callback_data: rawptr,
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	ctx: runtime.Context,
}

@private
_callback_wrapper :: proc "c" (
	input, output: rawptr,
    frame_count: c.ulong,
    time_info: ^pa.StreamCallbackTimeInfo,
    status_flags: pa.StreamCallbackFlags,
    user_data: rawptr,
) -> pa.StreamCallbackResult {
	stream := cast(^Audio_Stream) user_data

	context = stream.ctx
	output_buf: []f32 = (cast([^]f32)output)[:frame_count*2]

	status := stream.stream_callback(stream.callback_data, output_buf, 2, 48000)
	if status == .Finish {
		stream.event_callback(stream.callback_data, .Finish)
	}

	for &f in output_buf {
		f *= stream.volume
	}

	return .Continue
}

audio_create_stream :: proc(
	stream: ^Audio_Stream,
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	callback_data: rawptr
) -> (ok: bool) {
	@static initialized: bool
	if !initialized {
		if pa.Initialize() != .NoError {
			return false
		}
		initialized = true
	}

	stream.callback_data = callback_data
	stream.stream_callback = stream_callback
	stream.event_callback = event_callback
	stream.ctx = context
	stream.volume = 1

	pa.OpenDefaultStream(&stream.stream, 0, 2, pa.SampleFormat_Float32, 48000, 24000, _callback_wrapper, stream)
	pa.StartStream(stream.stream)

	return true
}

audio_drop_buffer :: proc(stream: ^Audio_Stream, loc := #caller_location) {
	log.debug(loc)
	if stream.stream == nil {return}
	pa.AbortStream(stream.stream)
	if stream.event_callback != nil {
		//stream.event_callback(stream.callback_data, .DropBuffer)
	}
	pa.StartStream(stream.stream)
}

audio_pause :: proc(stream: ^Audio_Stream) {
	if stream.stream == nil {return}
	if stream.event_callback != nil {
		stream.event_callback(stream.callback_data, .Pause)
	}
	pa.StopStream(stream.stream)
}

audio_resume :: proc(stream: ^Audio_Stream) {
	if stream.event_callback != nil {
		stream.event_callback(stream.callback_data, .Resume)
	}
	pa.StartStream(stream.stream)
}

audio_set_volume :: proc(stream: ^Audio_Stream, volume: f32) {
	stream.volume = volume
}

audio_get_volume :: proc(stream: ^Audio_Stream) -> (volume: f32) {
	return stream.volume
}

audio_get_buffer_timestamp :: proc(stream: ^Audio_Stream) -> (time.Tick, bool) {
	return {}, true
}

audio_destroy_stream :: proc(stream: ^Audio_Stream) {
	pa.CloseStream(stream.stream)
}
