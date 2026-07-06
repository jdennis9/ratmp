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
package shared

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:time"

@(deferred_out=_TIMED_SCOPE_EXIT)
TIME_SCOPE :: proc(
	name_args: ..any, sep := " ", loc := #caller_location
) -> (string, time.Tick, runtime.Source_Code_Location) {
	name := fmt.aprint(..name_args, sep=sep, allocator=context.allocator)
	start := time.tick_now()
	return name, start, loc
}

@(private="file")
_TIMED_SCOPE_EXIT :: proc(name: string, start: time.Tick, loc: runtime.Source_Code_Location) {
	duration := time.tick_since(start)
	log.debugf("[TIMER] %s: %gms", name, time.duration_milliseconds(duration), location = loc)
	delete(name)
}

string_from_array :: proc(arr: []u8) -> string {
	if arr[len(arr)-1] == 0 do return string(cstring(raw_data(arr)))
	else do return string(arr[:])
}
