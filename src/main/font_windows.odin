#+private file
package main

import "core:slice"
import "core:strings"
import "core:log"
import "core:unicode/utf16"
import win "core:sys/windows"
import "base:runtime"
import misc "src:bindings/windows_misc"
import "core:mem"

@private
font_init_windows :: proc() -> Error {

	_font_impl_free = proc(f: System_Font) {
		if f.handle != nil do free(f.handle)
	}

	_font_impl_get_font_path = proc(
		f: System_Font, allocator: mem.Allocator
	) -> (path: string, error: Error) {
		buf: [512]u8

		if f.handle == nil {
			error = Custom_Error.NotFound
			return
		}

		if !misc.get_font_file_from_logfont(auto_cast f.handle, cstring(&buf[0]), auto_cast len(buf)) {
			error = Custom_Error.NotFound
			return
		}

		path = strings.clone(string_from_array(buf[:]), allocator) or_return
		return
	}

	_font_impl_list_system_fonts = proc(
		allocator: mem.Allocator
	) -> (out: []System_Font, error: Error) {

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

			sf.name = strings.clone_to_cstring(string_from_array(buf[:]), args.allocator)

			append(&args.output, sf)

			return 1
		}

		win.EnumFontFamiliesExW(hdc, &lf, enum_proc, cast(win.LPARAM) cast(uintptr) &args, 0)

		out = slice.clone(args.output[:], allocator)
		return
	}

	return nil
}
