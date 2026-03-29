package main

import "core:mem"

System_Font :: struct {
	handle: rawptr,
	name: cstring,
}

_font_impl_list_system_fonts: proc(allocator: mem.Allocator) -> ([]System_Font, Error)
_font_impl_get_font_path: proc(f: System_Font, allocator: mem.Allocator) -> (string, Error)
_font_impl_free: proc(f: System_Font)

font_list_system_fonts :: proc(allocator: mem.Allocator) -> (fonts: []System_Font, error: Error) {
	if _font_impl_list_system_fonts != nil {
		return _font_impl_list_system_fonts(allocator)
	}
	return
}

font_get_path :: proc(f: System_Font, allocator: mem.Allocator) -> (path: string, error: Error) {
	if _font_impl_get_font_path != nil {
		return _font_impl_get_font_path(f, allocator)
	}
	return
}

font_free :: proc(f: System_Font) {
	if _font_impl_free != nil {
		_font_impl_free(f)
	}
}

font_from_name :: proc(fonts: []System_Font, name: string) -> (f: System_Font, found: bool) {
	for font in fonts {
		if string(font.name) == name do return font, true
	}
	return
}
