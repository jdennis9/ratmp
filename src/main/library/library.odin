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

import "src:bindings/taglib"
import "core:hash"
import "base:runtime"
import "src:main/shared"
import "core:net"
import "core:slice"
import "core:path/filepath"
import "core:os"
import "core:fmt"
import "core:testing"
import "core:strings"
import "core:mem"
import hm "core:container/handle_map"
import "core:log"

Shared_String_ID :: i16
Artist_ID        :: Shared_String_ID
Genre_ID         :: Shared_String_ID
Album_ID         :: Shared_String_ID
Track_ID         :: hm.Handle32
Playlist_ID      :: hm.Handle32

Error :: union {
	bool,
	os.Error,
	mem.Allocator_Error,
}

Shared_String_Type :: enum u8 {
	Artist,
	Album,
	Genre,
}

Shared_String :: struct {
	name:       string,
	lower_name: string,
}

Track :: struct {
	title:      string,
	url:        string,
	genres:     []Genre_ID,
	artists:    []Artist_ID,
	file_date:  i64,
	file_size:  i64,
	handle:     Track_ID,
	duration:   i32,
	track:      i32,
	year:       i32,
	samplerate: i32,
	channels:   i32,
	bitrate:    i32,
	album:      Album_ID,
	format:     Audio_File_Format,
}

Track_Map        :: hm.Dynamic_Handle_Map(Track, Track_ID)
Track_Iterator   :: hm.Dynamic_Handle_Map_Iterator(Track_Map)

Track_Totals :: struct {
	length:    int,
	duration:  i64,
	file_size: i64,
}

Playlist :: struct {
	serial:      uint,
	save_serial: uint,
	file:        string,
	handle:      Playlist_ID,
	name:        string,
	tracks:      [dynamic]Track_ID,
	uid:         shared.UID,
}

Playlist_Map      :: hm.Dynamic_Handle_Map(Playlist, Playlist_ID)
Playlist_Iterator :: hm.Dynamic_Handle_Map_Iterator(Playlist_Map)

Folder_Cover_Art :: struct {
	folder: string,
	image:  string,
}

Library :: struct {
	tracks_serial:    uint,
	tracks:           Track_Map,
	shared_strings:   [Shared_String_Type][dynamic]Shared_String,
	tag_arena:        mem.Dynamic_Arena,
	tag_allocator:    mem.Allocator,
	playlists:        Playlist_Map,
	playlists_serial: uint,
	config:           Library_Config,
	folder_root:      Folder,
	folder_arena:     mem.Dynamic_Arena,
	folder_allocator: mem.Allocator,
	folder_serial:    uint,
	folder_cover_art: map[u64]Folder_Cover_Art, // folder hash -> cover art path

	tracking_allocators: struct {
		tag:         mem.Tracking_Allocator,
		folder_tree: mem.Tracking_Allocator,
	},
}

Library_Config :: struct {
	enable_memory_tracking:  bool,
	prefer_folder_cover_art: bool,
}

@(private="file")
_library: Library

init :: proc(config: Library_Config) -> shared.Error {
	l := &_library
	l.config = config

	for &ss in l.shared_strings do reserve(&ss, 128)

	mem.dynamic_arena_init(&l.tag_arena, alignment = 4)
	l.tag_allocator = mem.dynamic_arena_allocator(&l.tag_arena)

	mem.dynamic_arena_init(&l.folder_arena)
	l.folder_allocator = mem.dynamic_arena_allocator(&l.folder_arena)

	if config.enable_memory_tracking {
		l.tag_allocator    = shared.track_allocator(l.tag_allocator, &l.tracking_allocators.tag)
		l.folder_allocator = shared.track_allocator(l.folder_allocator, &l.tracking_allocators.folder_tree)
	}

	// @TEMP: http audio stream test
	{
		tags := Track_Tags {
			artist = "TEST",
			album  = "INTERNET TEST",
			format = .Mp3,
			title  = "INTERNET TEST",
		}

		add_track(tags, "https://audio-edge-d34v9.syd.o.radiomast.io/ref-128k-mp3-stereo")
	}

	return nil
}

shutdown :: proc() {
	l := &_library

	if l.config.enable_memory_tracking {
		mem.tracking_allocator_destroy(&l.tracking_allocators.tag)
		mem.tracking_allocator_destroy(&l.tracking_allocators.folder_tree)
	}

	mem.dynamic_arena_destroy(&l.tag_arena)
	mem.dynamic_arena_destroy(&l.folder_arena)
	hm.dynamic_destroy(&l.tracks)
	for ss in l.shared_strings {
		delete(ss)
	}
}

update :: proc() {
	l := &_library

	if l.folder_serial != l.tracks_serial {
		l.folder_serial = l.tracks_serial
		shared.TIME_SCOPE("Build folder tree")
		free_all(l.folder_allocator)
		build_folder_tree(&l.folder_root, l.folder_allocator)
	}
}

get_playlists_serial :: proc() -> uint {return _library.playlists_serial}
get_tracks_serial :: proc() -> uint {return _library.tracks_serial}
get_root_folder :: proc() -> ^Folder {return &_library.folder_root}
get_folder_tree_serial :: proc() -> uint {return _library.folder_serial}

join_shared_strings :: proc(type: Shared_String_Type, ids: []Shared_String_ID, allocator: mem.Allocator) -> string {
	if len(ids) == 0 do return ""
	s := make([]string, len(ids), context.temp_allocator)
	get_shared_strings(type, ids, s)
	return strings.join(s, ", ", allocator)
}

dump_tracks :: proc() {
	l := &_library

	iter := hm.dynamic_iterator_make(&l.tracks)

	for track, _ in hm.dynamic_iterate(&iter) {
		fmt.println(track)
	}
}

make_track_iterator :: proc() -> Track_Iterator {
	return hm.dynamic_iterator_make(&_library.tracks)
}

iterate_tracks :: proc(iter: ^Track_Iterator) -> (track: ^Track, ok: bool) {
	ptr, _ := hm.dynamic_iterate(iter) or_return
	return ptr, true
}

add_track :: proc(tags: Track_Tags, url: string) -> (id: Track_ID, ok: bool) {
	track: Track

	l := &_library

	split_shared_strings :: proc(s: string, type: Shared_String_Type) -> []Shared_String_ID {
		l := &_library
		parts := strings.split(s, ",", context.allocator)
		
		if len(parts) == 0 do return nil
		defer delete(parts)

		output := make([]Shared_String_ID, len(parts), l.tag_allocator)
		for &p, i in parts {
			output[i] = _add_shared_string(type, strings.trim_space(p))
		}

		return output
	}

	track.album      = auto_cast _add_shared_string(.Album, tags.album)
	track.title      = strings.clone(tags.title, l.tag_allocator)
	track.url        = strings.clone(url, l.tag_allocator)
	track.samplerate = tags.samplerate
	track.bitrate    = tags.bitrate
	track.channels   = tags.channels
	track.duration   = tags.duration
	track.file_date  = tags.file_date
	track.file_size  = tags.file_size
	track.track      = tags.track
	track.year       = tags.year
	track.format     = tags.format
	track.artists    = split_shared_strings(tags.artist, .Artist)
	track.genres     = split_shared_strings(tags.genre, .Genre)

	assert(track.title != "")
	assert(track.url != "")
	
	id = hm.dynamic_add(&l.tracks, track)
	ok = true

	l.tracks_serial += 1

	return
}

remove_track :: proc(id: Track_ID) {
	// We don't worry about freeing up track memory here because
	// 99% of the time tracks are only being added, not removed.
	// We are only leaking a few bytes here anyway.

	hm.dynamic_remove(&_library.tracks, id)

	_library.tracks_serial += 1
}

get_track :: proc(id: Track_ID) -> (track: Track, found: bool) {
	l := &_library
	ptr := hm.dynamic_get(&l.tracks, id) or_return
	track = ptr^
	found = true
	return
}

get_tracks :: proc(ids: []Track_ID, allocator: mem.Allocator) -> []Track {
	count: int
	l := &_library
	tracks := make([]Track, len(ids), allocator)

	for id in ids {
		t := get_track(id) or_continue
		tracks[count] = t
		count += 1
	}

	return tracks[:count]
}

get_all_tracks :: proc(allocator: mem.Allocator) -> []Track {
	l := &_library

	tracks := make([]Track, hm.dynamic_len(l.tracks), allocator)
	iter   := make_track_iterator()
	count  := 0

	for track in iterate_tracks(&iter) {
		tracks[count] = track^
		count += 1
	}

	return tracks[:count]
}

get_all_track_ids :: proc(allocator: mem.Allocator) -> []Track_ID {
	l := &_library

	ids   := make([]Track_ID, hm.dynamic_len(l.tracks), allocator)
	iter  := make_track_iterator()
	count := 0

	for track in iterate_tracks(&iter) {
		ids[count] = track.handle
		count += 1
	}

	return ids[:count]
}

find_track_by_url :: proc(url: string) -> (id: Track_ID, found: bool) {
	iter := make_track_iterator()

	for track in iterate_tracks(&iter) {
		if track.url == url {
			return track.handle, true
		}
	}

	return
}

get_playlist :: proc(id: Playlist_ID) -> (^Playlist, bool) {
	return hm.dynamic_get(&_library.playlists, id)
}

make_playlist_iterator :: proc() -> Playlist_Iterator {
	return hm.dynamic_iterator_make(&_library.playlists)
}

iterate_playlists :: proc(iter: ^Playlist_Iterator) -> (pl: ^Playlist, ok: bool) {
	ptr, _ := hm.dynamic_iterate(iter) or_return
	return ptr, true
}

create_playlist :: proc(name: string) -> (Playlist_ID, bool) {
	l := &_library

	playlist := Playlist {
		name = name != "" ? strings.clone(name, l.tag_allocator) : "",
		uid  = shared.generate_uid(),
	}

	id, error := hm.dynamic_add(&l.playlists, playlist)

	if error != nil do return {}, false

	l.playlists_serial += 1

	return id, true
}

remove_playlist :: proc(id: Playlist_ID) -> bool {
	l := &_library

	playlist := hm.dynamic_get(&l.playlists, id) or_return

	if playlist.file != "" {
		os.remove(playlist.file)
	}

	l.playlists_serial += 1

	return true
}

rename_playlist :: proc(id: Playlist_ID, new_name: string) -> bool {
	l := &_library

	playlist := hm.dynamic_get(&l.playlists, id) or_return
	playlist.name = strings.clone(new_name, l.tag_allocator)
	playlist.serial += 1

	l.playlists_serial += 1

	return true
}

add_to_playlist :: proc(id: Playlist_ID, tracks: []Track_ID) -> bool {
	l := &_library

	playlist := hm.dynamic_get(&l.playlists, id) or_return

	for track in tracks {
		if !slice.contains(playlist.tracks[:], track) {
			append(&playlist.tracks, track)
		}
	}

	return true
}

add_to_track_totals :: proc(t: ^Track_Totals, track: Track) {
	t.duration += i64(track.duration)
	t.file_size += i64(track.file_size)
	t.length += 1
}

sum_track_totals :: proc(tracks: []Track_ID) -> (t: Track_Totals) {
	for id in tracks {
		track := get_track(id) or_continue
		add_to_track_totals(&t, track)
	}

	return
}

add_cover_art :: proc(folder: string, art_path: string) {
	l := &_library

	cleaned, _ := filepath.clean(folder)
	defer delete(cleaned)

	folder_hash := hash.fnv64a(transmute([]byte) folder)

	l.folder_cover_art[folder_hash] = {
		folder = strings.clone(folder, l.tag_allocator),
		image  = strings.clone(art_path, l.tag_allocator),
	}
}

find_track_cover_art :: proc(
	track_id: Track_ID,
	allocator: mem.Allocator
) -> (data: []byte, found: bool) {
	l := &_library
	track := get_track(track_id) or_return

	get_folder_art :: proc(track: Track, allocator: mem.Allocator) -> (data: []byte, found: bool) {
		l := &_library

		path := url_to_filepath(track.url) or_return
		path, _ = filepath.clean(filepath.dir(path))
		defer delete(path)

		folder_hash := hash.fnv64a(transmute([]byte) path)
		folder_art := l.folder_cover_art[folder_hash] or_return

		read_error: os.Error
		data, read_error = os.read_entire_file_from_path(folder_art.image, allocator)

		if read_error != nil {
			log.error(read_error)
			return
		}

		found = true
		return
	}

	get_embedded_art :: proc(track: Track, allocator: mem.Allocator) -> (data: []byte, found: bool) {
		path := url_to_filepath(track.url) or_return
		file := open_file_for_taglib(path)
		if file == nil do return
		defer taglib.file_free(file)

		pic_data: taglib.Complex_Property_Picture_Data

		picture := taglib.complex_property_get(file, "PICTURE")
		if picture == nil do return
		taglib.picture_from_complex_property(picture, &pic_data)
		if pic_data.data == nil do return

		data = slice.clone(slice.from_ptr(pic_data.data, auto_cast pic_data.size), allocator)
		found = true
		return
	}

	if l.config.prefer_folder_cover_art {
		data, found = get_folder_art(track, allocator)
		if found do return
		data, found = get_embedded_art(track, allocator)
		return
	}
	else {
		data, found = get_embedded_art(track, allocator)
		if found do return
		data, found = get_folder_art(track, allocator)
		return
	}
}

@private
_add_shared_string :: proc(type: Shared_String_Type, name: string) -> i16 {
	l := &_library

	for s, i in l.shared_strings[type] {
		if s.name == name do return auto_cast i
	}

	s := Shared_String {
		name       = strings.clone(name, l.tag_allocator),
		lower_name = strings.to_lower(name, l.tag_allocator),
	}

	index := len(l.shared_strings[type])
	append(&l.shared_strings[type], s)

	return auto_cast index
}

get_shared_string :: proc(type: Shared_String_Type, id: Shared_String_ID) -> string {
	return _library.shared_strings[type][id].name
}

get_shared_string_lower :: proc(type: Shared_String_Type, id: Shared_String_ID) -> string {
	return _library.shared_strings[type][id].lower_name
}

get_shared_strings :: proc(type: Shared_String_Type, ids: []Shared_String_ID, out: []string) {
	assert(len(ids) == len(out))

	for id, i in ids {
		out[i] = _library.shared_strings[type][id].name
	}
}

url_to_filepath :: proc(url: string) -> (string, bool) {
	if !strings.starts_with(url, "file://") do return "", false
	return strings.trim_prefix(url, "file://"), true
}

@test
test_add_tracks :: proc(t: ^testing.T) {
	testing.expect(t, init({}) == nil)
	defer shutdown()

	track := Track_Tags {
		title      = "A Particularly Long Title For A Song",
		artist     = "So, Many, Artists, Why?",
		genre      = "Bleep, Bloop, Music",
		album      = "A Collection of Computer Generated Music",
		bitrate    = 1000,
		channels   = 2,
		samplerate = 48000,
		duration   = 360,
		track      = 1,
		year       = 2001,
		file_size  = 1000000,
	}

	add_track(track, "file://C:/Music/Computer_Music.mp3")

	dump_tracks()
}
