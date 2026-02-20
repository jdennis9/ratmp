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
package sys

import "core:sort"
import "core:strings"

Font_Language :: enum {
	ChineseFull,
	ChineseSimplifiedCommon,
	Cyrillic,
	English,
	Greek,
	Japanese,
	Korean,
	Thai,
	Vietnamese,
	Icons,
}

Font_Languages :: bit_set[Font_Language]

Font_Desc :: struct {
	path: string,
	data: rawptr,
	size: f32,
	languages: Font_Languages,
}

Font_Handle_Common :: struct {
	name: [64]u8,
}

font_handle_from_name :: proc(handles: []Font_Handle, name: string) -> (handle: Font_Handle, found: bool) {
	for &h in handles {
		if string(cstring(&h.name[0])) == name {
			return h, true
		}
	}

	return {}, false
}

@(private="file")
_sort_fonts :: proc(fonts_arg: []Font_Handle) {
	fonts := fonts_arg
	len_proc :: proc(iface: sort.Interface) -> int {
		fonts := cast(^[]Font_Handle) iface.collection
		return len(fonts)
	}

	swap_proc :: proc(iface: sort.Interface, a, b: int) {
		fonts := cast(^[]Font_Handle) iface.collection
		temp := fonts[a]
		fonts[a] = fonts[b]
		fonts[b] = temp
	}

	less_proc :: proc(iface: sort.Interface, a, b: int) -> bool {
		fonts := cast(^[]Font_Handle) iface.collection
		A := string(cstring(&fonts[a].name[0]))
		B := string(cstring(&fonts[b].name[0]))
		return strings.compare(A, B) < 0
	}

	iface: sort.Interface
	iface.collection = &fonts
	iface.len = len_proc
	iface.less = less_proc
	iface.swap = swap_proc

	sort.sort(iface)
}

get_font_list :: proc() -> []Font_Handle {
	@static font_list: []Font_Handle
	if font_list == nil {
		font_list = _list_fonts()
		_sort_fonts(font_list)
	}

	return font_list
}
