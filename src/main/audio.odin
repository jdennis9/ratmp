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
package main

AUDIO_MAX_CHANNELS :: 2

Audio_Impl :: enum {
	WASAPI,
}

Audio_Spec :: struct {
	samplerate, channels: int,
}

Audio_Callback_Event :: enum {
	Stream,
	BufferDropped,
	Paused,
	Resumed,
	TrackFinised,
}

Audio_Callback_Status :: enum {
	Continue,
	Finish,
}

Audio_Callback :: #type proc(
	data: rawptr, event: Audio_Callback_Event, buffer: []f32, spec: Audio_Spec
) -> Audio_Callback_Status

_audio_impl_init:        proc(callback: Audio_Callback, callback_data: rawptr) -> bool
_audio_impl_shutdown:    proc()
_audio_impl_start:       proc() -> bool
_audio_impl_drop_buffer: proc()
_audio_impl_pause:       proc() -> bool
_audio_impl_resume:      proc() -> bool
_audio_impl_is_paused:   proc() -> bool
_audio_impl_stop:        proc()
_audio_impl_get_volume:  proc() -> f32
_audio_impl_set_volume:  proc(v: f32)

audio_init :: proc(callback: Audio_Callback, callback_data: rawptr) -> bool {
	return _audio_impl_init(callback, callback_data)
}

audio_shutdown :: proc() {
	_audio_impl_stop()
	_audio_impl_shutdown()
}

audio_start :: proc() -> bool {
	return _audio_impl_start()
}

audio_drop_buffer :: proc() {
	_audio_impl_drop_buffer()
}

audio_stop :: proc() {
	_audio_impl_stop()
}

audio_pause :: proc() -> bool {
	return _audio_impl_pause()
}

audio_resume :: proc() -> bool {
	return _audio_impl_resume()
}

audio_is_paused :: proc() -> bool {
	return _audio_impl_is_paused()
}

audio_get_volume :: proc() -> f32 {
	return _audio_impl_get_volume()
}

audio_set_volume :: proc(v: f32) {
	_audio_impl_set_volume(v)
}
