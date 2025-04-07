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
package audio;

foreign import lib "../../cpp/cpp.lib";

Stream_Info :: struct {
	sample_rate, channels, delay_ms, buffer_duration_ms: i32,
};

Callback :: #type proc "c" (buffer: [^]f32, frames: i32, data: rawptr);

@(link_prefix="audio_")
foreign lib {
	run :: proc(callback: Callback, callback_data: rawptr, info: ^Stream_Info) -> b32 ---;
	kill :: proc() ---;
	interrupt :: proc() ---;
	set_volume :: proc(vol: f32) ---;
	get_volume :: proc() -> f32 ---;
};
