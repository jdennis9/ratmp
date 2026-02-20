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
package util

import "base:runtime"
import "core:encoding/json"
import "core:time"
import "core:log"

copy_string_to_buf :: proc "contextless" (buf: []u8, str: string) -> string {
	length := len(str)
	length = min(length, len(buf)-1)
	copy(buf, (transmute([]u8)str)[:length])
	buf[length] = 0

	return string(buf[:length])
}

swap :: proc "contextless" (a, b: ^$T) {
	temp := a^
	a^ = b^
	b^ = temp
}

dump_json :: proc(obj: $T, path: string, opt := json.Marshal_Options{}) -> (ok: bool) {
	data, marshal_error := json.marshal(obj, opt)
	if marshal_error != nil {return}
	defer delete(data)

	if os2.exists(path) {os2.remove(path)}
	file, file_error := os2.create(path)
	if file_error != nil {return}
	defer os2.close(file)

	os2.write(file, data)

	return true
}

load_json :: proc(obj: ^$T, path: string, allocator := context.allocator) -> (ok: bool) {
	data, read_error := os2.read_entire_file_from_path(path, context.allocator)
	if read_error != nil {return}
	defer delete(data)
	json.unmarshal(data, obj, allocator=allocator)
	return true
}

decode_utf8_to_runes :: proc "contextless" (buf: []rune, str: string) -> []rune {
	n: int
	m := len(buf)

	for r in str {
		if n >= m {
			break
		}

		buf[n] = r
		n += 1
	}

	return buf[:n]
}

clock_from_seconds :: proc "contextless" (in_sec: int) -> (hour, min, sec: int) {
	sec = in_sec
	hour = sec / time.SECONDS_PER_HOUR
	sec -= hour * time.SECONDS_PER_HOUR
	min = sec / time.SECONDS_PER_MINUTE
	sec -= min * time.SECONDS_PER_MINUTE
	return
}


@(deferred_in_out=_SCOPED_TIMER_END)
SCOPED_TIMER :: proc(name: string, loc := #caller_location) -> time.Tick {
	return time.tick_now()
}

@(private="file")
_SCOPED_TIMER_END :: proc(name: string, loc: runtime.Source_Code_Location, start: time.Tick) {
	length := time.tick_since(start)
	log.debugf("%s: %fms", name, time.duration_milliseconds(length), location = loc)
}

