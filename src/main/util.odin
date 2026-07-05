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

import "base:runtime"
import "core:os"
import "core:fmt"
import "core:log"
import "core:time"
import "core:hash"

HASH_ALGO_64 :: "fnv64a"
HASH_ALGO_32 :: "fnv32a"

string_from_array :: proc(arr: []u8) -> string {
	if arr[len(arr)-1] == 0 do return string(cstring(raw_data(arr)))
	else do return string(arr[:])
}

set_cstring_buf :: proc(buf: []u8, str: string) -> bool {
	if len(str) > len(buf)-1 do return false
	copy(buf[:len(buf)-1], str)
	buf[len(str)] = 0
	return true
}

stable_hash_string_64 :: proc(str: string) -> u64 {
	return hash.fnv64a(transmute([]byte) str)
}

stable_hash_string_32 :: proc(str: string) -> u32 {
	return hash.fnv32a(transmute([]byte) str)
}

format_duration :: proc(buf: []u8, seconds: int) {
	h, m, s := time.clock_from_seconds(auto_cast seconds)
	fmt.bprintf(buf, "%02d:%02d:%02d", h, m ,s)
}

ensure_dir :: proc(path: string) {
	if os.exists(path) do return
	os.make_directory_all(path)
}

audio_channels_to_string :: proc(ch: int) -> (string, bool) {
	switch ch {
		case 1: return "Mono", true
		case 2: return "Stereo", true
	}

	return "", false
}
