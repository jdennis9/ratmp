package library

import "core:path/filepath"
import "core:unicode/utf16"
import "core:strings"
import "core:mem"
import "src:bindings/taglib"

Track_Tags :: struct {
	title:      string,
	artist:     string,
	genre:      string,
	album:      string,
	bitrate:    i32,
	channels:   i32,
	samplerate: i32,
	duration:   i32,
	track:      i32,
	year:       i32,
	file_date:  i64,
	file_size:  i64,
}

read_tags :: proc(filename: string, allocator: mem.Allocator) -> (tags: Track_Tags, ok: bool) {
	when ODIN_OS == .Windows {
		filename_u16 := make([]u16, len(filename) + 1, context.temp_allocator)
		utf16.encode_string(filename_u16, filename)
		file := taglib.file_new_wchar(cstring16(raw_data(filename_u16)))
	}
	else {
		file := taglib.file_new(strings.clone_to_cstring(filename, context.temp_allocator))
	}

	if file == nil do return
	defer taglib.file_free(file)

	tag := taglib.file_tag(file)

	if tag != nil {
		defer taglib.tag_free_strings()

		clone_tag :: proc(v: cstring, a: mem.Allocator) -> string {
			if v != nil && v != "" do return strings.clone(string(v), a)
			return ""
		}

		title  := taglib.tag_title(tag)
		album  := taglib.tag_album(tag)
		genre  := taglib.tag_genre(tag)
		artist := taglib.tag_artist(tag)

		tags.title  = clone_tag(title, allocator)
		tags.album  = clone_tag(album, allocator)
		tags.genre  = clone_tag(genre, allocator)
		tags.artist = clone_tag(artist, allocator)
		tags.year   = auto_cast taglib.tag_year(tag)
		tags.track  = auto_cast taglib.tag_track(tag)
	}

	audio_props := taglib.file_audioproperties(file)

	if audio_props != nil {
		tags.bitrate    = taglib.audioproperties_bitrate(audio_props)
		tags.channels   = taglib.audioproperties_channels(audio_props)
		tags.samplerate = taglib.audioproperties_samplerate(audio_props)
		tags.duration   = taglib.audioproperties_length(audio_props)
	}

	if tags.title == "" {
		tags.title = strings.clone(filepath.stem(filepath.base(filename)), allocator)
	}

	ok = true
	return
}

