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
package sys

import "base:runtime"

import win "core:sys/windows"
import "core:sort"
import "core:strings"

import "core:unicode/utf16"

import misc "src:bindings/windows_misc"

@(private="file")
_hdc: win.HDC

Font_Handle :: struct {
	using common: Font_Handle_Common,
	_win: struct {
		lf: win.LOGFONTW,
	},
}

_set_hdc :: proc(dc: win.HDC) {
	_hdc = dc
}

get_font_path :: proc(buf: []u8, h_arg: Font_Handle) -> (path: string, found: bool) {
	h := h_arg
	//h._win.lf.lfWeight = win.FW_REGULAR
	//h._win.lf.lfItalic = 0
	//h._win.lf.lfCharSet = win.ANSI_CHARSET
	h._win.lf.lfOutPrecision = win.OUT_TT_PRECIS
	h._win.lf.lfClipPrecision = win.CLIP_DEFAULT_PRECIS
	h._win.lf.lfQuality = win.ANTIALIASED_QUALITY
	//h._win.lf.lfPitchAndFamily = win.DEFAULT_PITCH | win.FF_DONTCARE
	misc.get_font_file_from_logfont(&h._win.lf, cstring(raw_data(buf)), auto_cast len(buf)) or_return
	return string(cstring(raw_data(buf))), true
}


@private
_list_fonts :: proc() -> []Font_Handle {
	Enum_Proc_Arg :: struct {
		output: ^[dynamic]Font_Handle,
		ctx: runtime.Context,
	}

	output: [dynamic]Font_Handle
	lf: win.LOGFONTW
	arg: Enum_Proc_Arg
	arg.ctx = context
	arg.output = &output

	enum_proc :: proc "system" (lf: ^win.ENUMLOGFONTW, metric: ^win.NEWTEXTMETRICW, font_type: win.DWORD, lparam: win.LPARAM) -> i32 {
		arg := cast(^Enum_Proc_Arg) cast(uintptr) lparam
		context = arg.ctx
		if lf.elfFullName[0] == '@' {return 1}
		h := Font_Handle {
			_win = {lf = lf.elfLogFont},
		}

		utf16.decode_to_utf8(h.name[:len(h.name)-1], lf.elfFullName[:wstring_length(&lf.elfFullName[0])])
		append(arg.output, h)
		return 1
	}

	win.EnumFontFamiliesExW(_hdc, &lf, enum_proc, cast(win.LPARAM) cast(uintptr) &arg, 0)

	
	return output[:]
}

