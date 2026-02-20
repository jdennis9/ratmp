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
package server

import "core:path/filepath"
import "base:runtime"
import "core:strings"

import "src:bindings/taglib"
import "src:util"

/*
	Always returns properties with a valid title
*/
track_properties_from_file :: proc(
	filename: string, allocator: runtime.Allocator
) -> (props: Track_Properties, ok: bool) #optional_ok {
	when ODIN_OS == .Windows {
		file := taglib.file_new_wchar(raw_data(util.win32_utf8_to_utf16(filename, context.temp_allocator)))
	}
	else {
		file := taglib.file_new(strings.clone_to_cstring(filename, context.temp_allocator))
	}

	props[.FileDate] = get_file_date(filename)
	
	if file == nil {
		props[.Title] = clone_string_with_null(filepath.base(filename), allocator)
		return
	}

	defer taglib.file_free(file)

	tag := taglib.file_tag(file)
	if tag != nil {
		defer taglib.tag_free_strings()

		artist := taglib.tag_artist(tag)
		album := taglib.tag_album(tag)
		genre := taglib.tag_genre(tag)
		title := taglib.tag_title(tag)

		props[.Artist] = clone_cstring_with_null(artist, allocator)
		props[.Album] = clone_cstring_with_null(album, allocator)
		props[.Genre] = clone_cstring_with_null(genre, allocator)
		props[.Title] = clone_cstring_with_null(title, allocator)
		props[.Year] = i64(taglib.tag_year(tag))
		props[.TrackNumber] = i64(taglib.tag_track(tag))
	}

	audio_props := taglib.file_audioproperties(file)
	if audio_props != nil {
		props[.Bitrate] = i64(taglib.audioproperties_bitrate(audio_props))
		props[.Duration] = i64(taglib.audioproperties_length(audio_props))
	}

	title := props[.Title].(string) or_else ""
	if title == "" {
		props[.Title] = clone_string_with_null(filepath.base(filename), allocator)
	}

	ok = true
	return
}

track_properties_clone :: proc(
	props: Track_Properties, allocator: Allocator
) -> (out: Track_Properties) {

	for p, id in props {
		switch v in p {
			case i64: out[id] = v
			case string: out[id] = clone_string_with_null(v, allocator)
		}
	}

	return
}

track_properties_destroy :: proc(props: ^Track_Properties) {
	for &p, _ in props {
		#partial switch v in p {
			case string: delete(v)
		}
	}
}

track_property_cstring :: proc(props: Track_Properties, id: Track_Property_ID) -> cstring {
	return strings.unsafe_string_to_cstring(props[id].(string) or_else string(cstring("")))
}
