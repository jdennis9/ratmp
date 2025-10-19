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
package server

import "base:runtime"
import "core:strings"

Sort_Order :: enum {
	Ascending,
	Descending,
}

Error :: enum {
	None,
	NameExists,
	FileError,
}

Path :: [512]u8

Allocator :: runtime.Allocator

clone_cstring_with_null :: proc(str: cstring, allocator: runtime.Allocator) -> string {
	return string(strings.clone_to_cstring(string(str), allocator))
}

clone_string_with_null :: proc(str: string, allocator: Allocator) -> string {
    out := make([]u8, len(str) + 1, allocator)
    copy(out, str)
    out[len(str)] = 0
    return string(out[:len(str)])
}
