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
}

Track_Map        :: hm.Dynamic_Handle_Map(Track, Track_ID)
Track_Iterator   :: hm.Dynamic_Handle_Map_Iterator(Track_Map)

Playlist :: struct {
	serial:      uint,
	save_serial: uint,
	file:        string,
	handle:      Playlist_ID,
	name:        string,
	tracks:      [dynamic]Track_ID,
}

Playlist_Map      :: hm.Dynamic_Handle_Map(Playlist, Playlist_ID)
Playlist_Iterator :: hm.Dynamic_Handle_Map_Iterator(Playlist_Map)

Library :: struct {
	tracks_serial:    uint,
	tracks:           Track_Map,
	shared_strings:   [Shared_String_Type][dynamic]Shared_String,
	tag_arena:        mem.Dynamic_Arena,
	tag_allocator:    mem.Allocator,
	playlists:        Playlist_Map,
	playlists_serial: uint,
	config:           Library_Config,

	tracking_allocators: struct {
		tag: mem.Tracking_Allocator,
	},
}

Library_Config :: struct {
	enable_memory_tracking: bool,
}

@(private="file")
_library: Library

init :: proc(config: Library_Config) -> bool {
	l := &_library
	l.config = config

	for &ss in l.shared_strings do reserve(&ss, 128)

	mem.dynamic_arena_init(&l.tag_arena, alignment = 4)
	l.tag_allocator = mem.dynamic_arena_allocator(&l.tag_arena)

	if config.enable_memory_tracking {
		mem.tracking_allocator_init(&l.tracking_allocators.tag, l.tag_allocator)
		l.tag_allocator = mem.tracking_allocator(&l.tracking_allocators.tag)
	}

	return true
}

shutdown :: proc() {
	l := &_library
	mem.dynamic_arena_destroy(&l.tag_arena)
	hm.dynamic_destroy(&l.tracks)
	for ss in l.shared_strings {
		delete(ss)
	}
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

	playlist := Playlist {name = name != "" ? strings.clone(name, l.tag_allocator) : ""}

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

@test
test_add_tracks :: proc(t: ^testing.T) {
	testing.expect(t, init({}))
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
