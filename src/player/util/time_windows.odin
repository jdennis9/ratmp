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
package util;

import win "core:sys/windows";

tick_now :: proc() -> i64 {
	counter: win.LARGE_INTEGER;
	win.QueryPerformanceCounter(&counter);
	return cast(i64) counter;
}

tick_frequency :: proc() -> i64 {
	freq: win.LARGE_INTEGER;
	win.QueryPerformanceFrequency(&freq);
	return cast(i64) freq;
}

ticks_to_millis :: proc(ticks: i64) -> f32 {
	freq := tick_frequency();
	return f32(f64(ticks) / f64(freq)) * 1000;
}
