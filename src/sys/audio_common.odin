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

Audio_Stream_Common :: struct {
	channels, samplerate: i32,
}
