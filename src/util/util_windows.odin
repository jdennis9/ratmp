package util

import "base:runtime"
import win "core:sys/windows"
import "core:strings"

win32_utf8_to_ansi :: proc(str: string, allocator: runtime.Allocator) -> cstring {
	u16_size := win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), nil, 0)
	u16_buf := make([]u16, u16_size)
	defer delete(u16_buf)

	win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), raw_data(u16_buf), auto_cast len(u16_buf))

	ansi_size := win.WideCharToMultiByte(win.CP_ACP, 0, raw_data(u16_buf), auto_cast len(u16_buf), nil, 0, nil, nil)
	ansi_buf := make([]u8, ansi_size)
	defer delete(ansi_buf)

	win.WideCharToMultiByte(win.CP_ACP, 0, raw_data(u16_buf), auto_cast len(u16_buf), raw_data(ansi_buf), auto_cast len(ansi_buf), nil, nil)

	return strings.clone_to_cstring(string(ansi_buf), allocator)
}

win32_utf8_to_utf16 :: proc(str: string, allocator: runtime.Allocator) -> []u16 {
	size := win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), nil, 0)
	buf := make([]u16, size, allocator)
	win.MultiByteToWideChar(win.CP_UTF8, 0, raw_data(str), auto_cast len(str), raw_data(buf), auto_cast len(buf))
	return buf
}
