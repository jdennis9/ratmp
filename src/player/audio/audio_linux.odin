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

import pa "../../bindings/portaudio"

// @NOTES:
// PortAudio doesn't have any way of discarding the current buffer that I know of, so the solution is to use a short
// buffer that is long enough for visualizers to have enough audio to work with, but short enough that seeking, changing track
// or changing volume don't feel super delayed.

@private
_audio: struct {
	ctx: runtime.Context,
	stream: pa.Stream,
	callback: Callback,
	callback_data: rawptr,
	devices: []Device_Props,
	info: Stream_Info,
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
	defer if !ok {shutdown()}
	ok = true
	return
}

shutdown :: proc() {
	pa.Terminate()
}

get_default_device_id :: proc() -> (Device_ID, bool) {
	return {}, true
}

start :: proc(device_id: ^Device_ID, callback: Callback, callback_data: rawptr) -> (info: Stream_Info, ok: bool) {
	_audio.callback = callback
	_audio.callback_data = callback_data
	_audio.info.channels = 2
	_audio.info.sample_rate = 48000

	_check(pa.OpenDefaultStream(&_audio.stream, 0, 2, pa.SampleFormat_Float32, 48000, 48000/8, _callback_wrapper, nil)) or_return
	_check(pa.StartStream(_audio.stream)) or_return

	info = _audio.info
	ok = true
	return
}

stop :: proc() {
	pa.StopStream(_audio.stream)
	pa.CloseStream(_audio.stream)
	_audio.stream = nil
}

interrupt :: proc() {
	//pa.AbortStream(_audio.stream)
	//pa.StartStream(_audio.stream)
}
set_volume :: proc(volume: f32) {}
get_volume :: proc() -> f32 {return 1}

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
	_audio.callback((cast([^]f32)output)[:frameCount * auto_cast _audio.info.channels], _audio.callback_data)
	return .Continue
}
