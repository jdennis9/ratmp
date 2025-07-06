package sys

import fc "src:bindings/fontconfig"

Font_Handle :: struct {
	using common: Font_Handle_Common,
	_linux: struct {
		pattern: ^fc.Pattern,
	}
}

get_font_path :: proc(buf: []u8, h: Font_Handle) -> (path: string, found: bool) {
	str: cstring
	pat := h._linux.pattern

	if fc.PatternGetString(pat, fc.FILE, 0, &str) == .Match {
		copy(buf[:len(buf)-1], string(str))
		return string(cstring(raw_data(buf))), true
	}

	return "", false
}

_font_list: []Font_Handle

@(private="file")
_list_fonts :: proc() -> (output: []Font_Handle) {
	cfg := fc.InitLoadConfigAndFonts()
	pat := fc.PatternCreate()
	os := fc.object_set_build_family_file()
	fs := fc.FontList(cfg, pat, os)

	output = make([]Font_Handle, fs.nfont)

	for font, i in fs.fonts[:fs.nfont] {
		family: cstring
		handle := &output[i]
		handle._linux.pattern = fs.fonts[i]

		if fc.PatternGetString(font, fc.FAMILY, 0, &family) == .Match {
			copy(handle.name[:len(handle.name)-1], string(family))
		}
	}

	return
}

@(private="file")
@fini
_free_font_list :: proc() {
	delete(_font_list)
}

get_font_list :: proc() -> []Font_Handle {
	if _font_list == nil {_font_list = _list_fonts()}

	return _font_list
}
