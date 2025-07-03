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
