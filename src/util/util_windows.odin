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
import win "core:sys/windows"
import "core:strings"

win32_utf8_to_ansi :: proc(str: string, allocator: runtime.Allocator) -> cstring {
	u16_size := win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), nil, 0)
	u16_buf := make([]u16, u16_size)
	defer delete(u16_buf)
	cstr := cstring16(raw_data(u16_buf))

	win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), raw_data(u16_buf), auto_cast len(u16_buf))

	ansi_size := win.WideCharToMultiByte(win.CP_ACP, 0, cstr, auto_cast len(u16_buf), nil, 0, nil, nil)
	ansi_buf := make([]u8, ansi_size)
	defer delete(ansi_buf)

	win.WideCharToMultiByte(win.CP_ACP, 0, cstr, auto_cast len(u16_buf), raw_data(ansi_buf), auto_cast len(ansi_buf), nil, nil)

	return strings.clone_to_cstring(string(ansi_buf), allocator)
}

win32_utf8_to_utf16 :: proc(str: string, allocator: runtime.Allocator) -> []u16 {
	size := win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), nil, 0)
	buf := make([]u16, size, allocator)
	win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), raw_data(buf), auto_cast len(buf))
	return buf
}
