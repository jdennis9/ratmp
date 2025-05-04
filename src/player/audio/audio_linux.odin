/*
	RAT MP: A lightweight graphical music player
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
package audio

import "base:runtime"
import "core:log"
import C "core:c"

import pa "bindings:portaudio"

// @NOTES:
// PortAudio doesn't have any way of discarding the current buffer that I know of, so the solution is to use a short
// buffer that is long enough for visualizers to have enough audio to work with, but short enough that seeking, changing track
// or changing volume don't feel super delayed.

@private
_audio: struct {
	ctx: runtime.Context,
}

Stream :: struct {
	using com: _Stream_Common,
	_pa: struct {stream: pa.Stream, volume: f32,}
}

@private
_check :: proc(error: pa.ErrorCode, loc := #caller_location, expr := #caller_expression) -> bool {
	if error != .NoError {
		log.error(loc, pa.GetErrorText(error))
		return false
	}

	return true
}

init :: proc() -> (ok: bool) {
	_audio.ctx = context
	_check(pa.Initialize()) or_return
	ok = true
	return
}

shutdown :: proc() {
	pa.Terminate()
}

get_default_device_id :: proc() -> (Device_ID, bool) {
	return {}, true
}

open_stream :: proc(device_id: ^Device_ID, callback: Callback, callback_data: rawptr) -> (stream: ^Stream, ok: bool) {
	stream = new(Stream)
	defer if !ok {free(stream)}

	stream._callback = callback
	stream._callback_data = callback_data
	stream.channels = 2
	stream.samplerate = 48000
	stream._pa.volume = 1

	_check(pa.OpenDefaultStream(&stream._pa.stream, 0, 2, pa.SampleFormat_Float32, 48000, 24000/8, _callback_wrapper, stream))
	_check(pa.StartStream(stream._pa.stream))

	ok = true
	return
}

close_stream :: proc(stream: ^Stream) {
	if stream == nil {return}
	pa.StopStream(stream._pa.stream)
	pa.CloseStream(stream._pa.stream)
	free(stream)
}

stream_interrupt :: proc(stream: ^Stream) {
}

stream_set_volume :: proc(stream: ^Stream, volume: f32) {
	if stream == nil {return}
	stream._pa.volume = volume
}

stream_get_volume :: proc(stream: ^Stream) -> f32 {
	if stream == nil {return}
	return stream._pa.volume
}

enumerate_devices :: proc() -> (devices: []Device_Props, ok: bool) {
	return {}, true
}

@private
_callback_wrapper :: proc "c" (
	input, output: rawptr,
	frameCount: C.ulong,
	timeInfo: ^pa.StreamCallbackTimeInfo,
	statusFlags: pa.StreamFlags,
	userData: rawptr,
) -> pa.StreamCallbackResult {
	context = _audio.ctx
	stream := cast(^Stream) userData
	sample_count := int(frameCount) * stream.channels
	buffer := (cast([^]f32) output)[:sample_count]

	stream._callback(stream._callback_data, buffer)

	for &f in buffer {f *= stream._pa.volume}

	return .Continue
}
