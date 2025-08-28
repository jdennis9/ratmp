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
