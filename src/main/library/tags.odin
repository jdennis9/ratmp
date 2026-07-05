/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
package library

import "core:time"
import "core:os"
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
	format:     Audio_File_Format,
}

open_file_for_taglib :: proc(filename: string) -> taglib.File {
	when ODIN_OS == .Windows {
		filename_u16 := make([]u16, len(filename) + 1, context.temp_allocator)
		utf16.encode_string(filename_u16, filename)
		return taglib.file_new_wchar(cstring16(raw_data(filename_u16)))
	}
	else {
		return taglib.file_new(strings.clone_to_cstring(filename, context.temp_allocator))
	}
}

read_tags :: proc(filename: string, allocator: mem.Allocator) -> (tags: Track_Tags, ok: bool) {
	tags.format = audio_file_format_from_extension(filepath.ext(filename)) or_return

	file := open_file_for_taglib(filename)

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

	file_info, stat_error := os.stat(filename, context.allocator)
	if stat_error == nil {
		defer os.file_info_delete(file_info, context.allocator)

		tags.file_size = file_info.size
		tags.file_date = time.to_unix_seconds(file_info.creation_time)
	}

	ok = true
	return
}

