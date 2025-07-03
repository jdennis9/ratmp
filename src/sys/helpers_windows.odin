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

@private
win32_safe_release :: proc(p: ^^$T) {
	if p^ != nil {
		p^->Release()
		p^ = nil
	}
}

