package server

// Copy string to buffer, guaranteeing null-terminator
copy_string_to_buf :: proc(buf: []u8, str: string) -> string {
	length := len(str)
	length = min(length, len(buf)-1)
	copy(buf, (transmute([]u8)str)[:length])
	buf[length] = 0

	return string(buf[:length])
}
