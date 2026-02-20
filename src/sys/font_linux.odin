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

import "core:log"
import "core:fmt"
import "core:sort"
import fc "src:bindings/fontconfig"

Font_Handle :: struct {
	using common: Font_Handle_Common,
	_linux: struct {
		pattern: ^fc.Pattern,
	}
}

get_font_path :: proc(buf: []u8, h: Font_Handle) -> (path: string, found: bool) {
	str: cstring
	pat := h._linux.pattern

	if fc.PatternGetString(pat, fc.FILE, 0, &str) == .Match {
		copy(buf[:len(buf)-1], string(str))
		return string(cstring(raw_data(buf))), true
	}

	return "", false
}

@private
_list_fonts :: proc() -> (output: []Font_Handle) {
	cfg := fc.InitLoadConfigAndFonts()
	pat := fc.PatternCreate()
	os := fc.object_set_build_family_file()
	fs := fc.FontList(cfg, pat, os)

	out: [dynamic]Font_Handle
	reserve(&out, fs.nfont)

	for font, i in fs.fonts[:fs.nfont] {
		name: cstring
		handle: Font_Handle
		
		if fc.PatternGetString(font, fc.FULLNAME, 0, &name) != .Match do continue
		if name == nil || string(name) == "" do continue

		handle._linux.pattern = fs.fonts[i]
		
		copy(handle.name[:len(handle.name)-1], string(name))

		append(&out, handle)
	}

	return out[:]
}

