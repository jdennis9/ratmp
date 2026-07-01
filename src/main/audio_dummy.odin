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

use_audio_dummy :: proc() {
	_audio_impl_init = proc(cb: Audio_Callback, cb_data: rawptr) -> bool {return true}
	_audio_impl_shutdown = proc() {}
	_audio_impl_start = proc() -> bool {return true}
	_audio_impl_stop = proc() {}
	_audio_impl_drop_buffer = proc() {}
	_audio_impl_get_volume = proc() -> f32 {return 1}
	_audio_impl_set_volume = proc(v: f32) {}
}
