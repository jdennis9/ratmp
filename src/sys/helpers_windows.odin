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
import win "core:sys/windows"
import "core:unicode/utf16"

win32_check :: proc(hr: win.HRESULT, expr := #caller_expression, loc := #caller_location) -> bool {
	if !win.SUCCEEDED(hr) {
		error_str_u16: [1024]u16
		error_str: [1024]u8
		length := win.FormatMessageW(win.FORMAT_MESSAGE_FROM_SYSTEM, 
			nil, auto_cast win.HRESULT_CODE(auto_cast hr), win.MAKELANGID(win.LANG_NEUTRAL, win.SUBLANG_DEFAULT),
			&error_str_u16[0], auto_cast len(error_str_u16), nil
		)
		utf16.decode_to_utf8(error_str[:len(error_str)-1], error_str_u16[:length])
		log.errorf("%s HRESULT %x (%s)", expr, hr, cstring(&error_str[0]))
		return false
	}

	return true
}

win32_safe_release :: proc(p: ^^$T) {
	if p^ != nil {
		p^->Release()
		p^ = nil
	}
}


wstring_length :: proc(str: [^]u16) -> int {
	i: int
	for {
		if str[i] == 0 {return i}
		i += 1
	}
}
