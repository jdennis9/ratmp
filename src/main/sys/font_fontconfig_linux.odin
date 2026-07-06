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

import "core:strings"
import "core:slice"
import "core:mem"

import fc "src:bindings/fontconfig"

font_init_fontconfig :: proc() -> Error {

	_font_impl_list_system_fonts = proc(
		allocator: mem.Allocator
	) -> (fonts: []System_Font, error: Error){
		buf: [dynamic]System_Font

		cfg := fc.InitLoadConfigAndFonts()
		pat := fc.PatternCreate()
		os := fc.object_set_build_family_file()
		fs := fc.FontList(cfg, pat, os)

		reserve(&buf, fs.nfont)

		for font, i in fs.fonts[:fs.nfont] {
			name: cstring
			handle: rawptr

			if fc.PatternGetString(font, fc.FULLNAME, 0, &name) != .Match do continue
			if name == nil || string(name) == "" do continue

			append(&buf, System_Font {
				handle = font,
				name = strings.clone_to_cstring(string(name), allocator) or_return,
			})
		}

		fonts = slice.clone(buf[:], allocator) or_return
		return
	}

	_font_impl_get_font_path = proc(
		f: System_Font, allocator: mem.Allocator
	) -> (path: string, error: Error) {
		str: cstring
		pat := cast(^fc.Pattern) f.handle
		if pat == nil do return "", Custom_Error.InvalidInput

		if fc.PatternGetString(pat, fc.FILE, 0, &str) == .Match {
			path = strings.clone(string(str), allocator)
		}
		else do error = Custom_Error.NotFound
		
		return
	}

	_font_impl_free = proc(f: System_Font) {
		if f.handle != nil {
			fc.PatternDestroy(cast(^fc.Pattern) f.handle)
		}
	}

	return nil
}

