package sys

import "core:log"
import win "core:sys/windows"

win32_check :: proc(hr: win.HRESULT, expr := #caller_expression, loc := #caller_location) -> bool {
	if !win.SUCCEEDED(hr) {
		log.error(expr, "HRESULT", hr)
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
