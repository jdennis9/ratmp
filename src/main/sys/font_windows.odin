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

import "src:main/shared"
import "core:slice"
import "core:strings"
import "core:log"
import "core:unicode/utf16"
import win "core:sys/windows"
import "base:runtime"
import misc "src:bindings/windows_misc"
import "core:mem"

font_init_windows :: proc() -> shared.Error {
	_font_impl_free = proc(f: System_Font) {
		if f.handle != nil do free(f.handle)
	}

	_font_impl_get_font_path = proc(
		f: System_Font, allocator: mem.Allocator
	) -> (path: string, error: shared.Error) {
		buf: [512]u8

		if f.handle == nil {
			error = shared.Error_Code.NotFound
			return
		}

		if !misc.get_font_file_from_logfont(auto_cast f.handle, cstring(&buf[0]), auto_cast len(buf)) {
			error = shared.Error_Code.NotFound
			return
		}

		path = strings.clone(shared.string_from_array(buf[:]), allocator) or_return
		return
	}

	_font_impl_list_system_fonts = proc(
		allocator: mem.Allocator
	) -> (out: []System_Font, error: shared.Error) {

		Args :: struct {
			output: [dynamic]System_Font,
			ctx: runtime.Context,
			allocator: mem.Allocator,
		}

		args := Args {ctx = context, allocator = allocator}
		defer delete(args.output)

		hdc := win.GetDC(nil)

		lf: win.LOGFONTW

		enum_proc := proc "system" (
			lf: ^win.ENUMLOGFONTW, _: ^win.NEWTEXTMETRICW, _: win.DWORD, lparam: win.LPARAM
		) -> i32 {
			buf: [256]u8
			args := cast(^Args) cast(uintptr) lparam
			context = args.ctx
			if lf.elfFullName[0] == '@' do return 1

			sf: System_Font
			sf.handle = new_clone(lf^, args.allocator)
			font_name := string16(cstring16(&lf.elfFullName[0]))
			if len(font_name) >= len(buf) {
				log.warn("Font name too long:", font_name)
				return 1
			}

			utf16.decode_to_utf8(buf[:255], transmute([]u16) font_name)

			sf.name = strings.clone_to_cstring(shared.string_from_array(buf[:]), args.allocator)

			append(&args.output, sf)

			return 1
		}

		win.EnumFontFamiliesExW(hdc, &lf, enum_proc, cast(win.LPARAM) cast(uintptr) &args, 0)

		out = slice.clone(args.output[:], allocator)
		return
	}

	return true
}
