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

import "core:strings"
import "core:sort"
import "core:mem"

System_Font :: struct {
	handle: rawptr,
	name: cstring,
}

_font_impl_list_system_fonts: proc(allocator: mem.Allocator) -> ([]System_Font, Error)
_font_impl_get_font_path: proc(f: System_Font, allocator: mem.Allocator) -> (string, Error)
_font_impl_free: proc(f: System_Font)

font_list_system_fonts :: proc(allocator: mem.Allocator) -> (fonts: []System_Font, error: Error) {
	if _font_impl_list_system_fonts != nil {
		fonts = _font_impl_list_system_fonts(allocator) or_return

		it := sort.Interface {
			collection = &fonts,
			len = proc(it: sort.Interface) -> int {
				return len((cast(^[]System_Font) it.collection)^)
			},
			less = proc(it: sort.Interface, a, b: int) -> bool {
				f := cast(^[]System_Font) it.collection
				return strings.compare(string(f[a].name), string(f[b].name)) < 0
			},
			swap = proc(it: sort.Interface, a, b: int) {
				f := cast(^[]System_Font) it.collection
				f[a], f[b] = f[b], f[a]
			},
		}

		sort.sort(it)
	}
	return
}

font_get_path :: proc(f: System_Font, allocator: mem.Allocator) -> (path: string, error: Error) {
	if _font_impl_get_font_path != nil {
		return _font_impl_get_font_path(f, allocator)
	}
	return
}

font_free :: proc(f: System_Font) {
	if _font_impl_free != nil {
		_font_impl_free(f)
	}
}

font_from_name :: proc(fonts: []System_Font, name: string) -> (f: System_Font, found: bool) {
	for font in fonts {
		if string(font.name) == name do return font, true
	}
	return
}
