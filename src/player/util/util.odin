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
package util

import "core:os"
import "core:fmt"

copy_cstring :: proc(dest: []u8, src: cstring) {
	length := min(len(src), len(dest)-1)
	copy(dest, (cast([^]u8)src)[:length])
	dest[length] = 0
}

// Copies string to buffer, ensuring the string is null-terminated
copy_string_to_buf :: proc(dest: []u8, src: string) {
	length := min(len(dest)-1, len(src))
	copy(dest, src)
	dest[length] = 0
}

decode_utf8_to_runes :: proc(buf: []rune, str: string) -> []rune {
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

json_sanitize_string :: proc(str: cstring, buf: []u8) -> string {
	value_slice := (cast([^]u8)str)[:len(str)]

	n: int
	for char in value_slice {
		defer n += 1

		if n >= len(buf) {break}
		if char == '"' || char == '\\' {
			buf[n] = '\\'
			n += 1
		}
		if n >= len(buf) {break}
		buf[n] = char
	}

	return string(buf[:n])
}

json_write_kv_pair_cstring :: proc(file: os.Handle, key, value: cstring, always_write := false) {
	length := len(value)
	if always_write || value != nil && length > 0 {
		buf: [512]u8
		sanitized := json_sanitize_string(value, buf[:])
		fmt.fprintln(file, "\"", key, "\"", ":", "\"", sanitized, "\",", sep ="", flush=false)
	}
}

json_write_kv_pair_int :: proc(file: os.Handle, key: string, value: int, always_write := false) {
	if always_write || value != 0 {
		fmt.fprintln(file, "\"", key, "\"", ":", value, ",", sep="", flush=false)
	}
}

json_write_kv_pair_bool :: proc(file: os.Handle, key: string, value: bool, always_write := false) {
	if always_write || value {
		fmt.fprintln(file, "\"", key, "\"", ":", value, ",", sep="", flush=false)
	}
}

json_write_kv_pair :: proc {
	json_write_kv_pair_int,
	json_write_kv_pair_cstring,
	json_write_kv_pair_bool,
}
