package taglib

import "core:c"

when ODIN_OS == .Windows {
	foreign import taglib {
		"tag_c.lib",
		"tag.lib",
		"zlib.lib",
		"../bindings.lib",
	}
}

when ODIN_OS == .Linux {
	foreign import taglib {
		"system:tag_c",
		"system:tag",
		"system:z",
	}
}

File :: distinct rawptr
Tag :: distinct rawptr
Audio_Properties :: distinct rawptr
BOOL :: c.int

Variant_Type :: enum {
	Void,
	Bool,
	Int,
	UInt,
	LongLong,
	ULongLong,
	Double,
	String,
	StringList,
	ByteVector,
	Type,
}

Variant :: struct {
	type: Variant_Type,
	size: c.uint,
	value: struct #raw_union {
		stringValue: cstring,
		byteVectorValue: cstring,
		stringListValue: ^cstring,
		boolValue: c.int,
		intValue: c.int,
		uIntValue: c.uint,
		longLongValue: c.longlong,
		uLongLongValue: c.ulonglong,
		doubleValue: c.double,
	},
}

Complex_Property_Attribute :: struct {
	key: cstring,
	value: Variant,
}

Complex_Property_Picture_Data :: struct {
	mimeType: cstring,
	description: cstring,
	pictureType: cstring,
	data: [^]byte,
	size: c.uint,
}

@(link_prefix="taglib_")
foreign taglib {
	file_new :: proc(filename: cstring) -> File ---
	file_new_wchar :: proc(filename: [^]u16) -> File ---
	file_free :: proc(file: File) ---
	file_tag :: proc(file: File) -> Tag ---
	file_audioproperties :: proc(file: File) -> Audio_Properties ---
	file_save :: proc(file: File) -> BOOL ---

	tag_title :: proc(tag: Tag) -> cstring ---
	tag_artist :: proc(tag: Tag) -> cstring ---
	tag_album :: proc(tag: Tag) -> cstring ---
	tag_comment :: proc(tag: Tag) -> cstring ---
	tag_genre :: proc(tag: Tag) -> cstring ---
	tag_year :: proc(tag: Tag) -> c.uint ---
	tag_track :: proc(tag: Tag) -> c.uint ---
	tag_free_strings :: proc() ---


	tag_set_title :: proc(tag: Tag, title: cstring) ---
	tag_set_artist :: proc(tag: Tag, artist: cstring) ---
	tag_set_album :: proc(tag: Tag, album: cstring) ---
	tag_set_genre :: proc(tag: Tag, genre: cstring) ---
	tag_set_comment :: proc(tag: Tag, comment: cstring) ---
	tag_set_year :: proc(tag: Tag, year: c.uint) ---
	tag_set_track :: proc(tag: Tag, track: c.uint) ---

	// In seconds
	audioproperties_length :: proc(props: Audio_Properties) -> c.int ---
	// In kb/s
	audioproperties_bitrate :: proc(props: Audio_Properties) -> c.int ---
	audioproperties_samplerate :: proc(props: Audio_Properties) -> c.int ---
	audioproperties_channels :: proc(props: Audio_Properties) -> c.int ---

	complex_property_get :: proc(file: File, prop: cstring) -> ^^^Complex_Property_Attribute ---
	picture_from_complex_property :: proc(props: ^^^Complex_Property_Attribute, pic: ^Complex_Property_Picture_Data) ---
	complex_property_free :: proc(props: ^^^Complex_Property_Attribute) ---
}
