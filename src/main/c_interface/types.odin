package c_interface

Track_ID :: distinct u32
Shared_String_ID :: distinct i16

String_View :: struct {data: [^]u8, len: i32}

Track :: struct {
	url:          String_View,
	title:        String_View,
	artists:      [^]Shared_String_ID,
	genres:       [^]Shared_String_ID,
	artist_count: i32,
	genre_count:  i32,
	track:        i32,
	bitrate:      i32,
	channels:     i32,
	samplerate:   i32,
	duration:     i32,
	year:         i32,
	file_date:    i64,
	file_size:    i64,
	album:        Shared_String_ID,
	has_album:    b8,
}

