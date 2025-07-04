package sys

Font_Language :: enum {
	ChineseFull,
	ChineseSimplifiedCommon,
	Cyrillic,
	English,
	Greek,
	Japanese,
	Korean,
	Thai,
	Vietnamese,
	Icons,
}

Font_Languages :: bit_set[Font_Language]

Font_Desc :: struct {
	path: string,
	data: rawptr,
	size: f32,
	languages: Font_Languages,
}

Font_Handle_Common :: struct {
	name: [64]u8,
}

font_handle_from_name :: proc(handles: []Font_Handle, name: string) -> (handle: Font_Handle, found: bool) {
	for &h in handles {
		if string(cstring(&h.name[0])) == name {
			return h, true
		}
	}

	return {}, false
}
