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

import "core:thread"
import "core:sync"
import "src:bindings/taglib"
import "core:hash"
import "base:runtime"
import "src:main/shared"
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

Error :: shared.Error

Shared_String_Type :: enum u8 {
	Artist,
	Album,
	Genre,
}

Shared_String :: struct {
	name:       string,
	lower_name: string,
	uid:        shared.UID,
	serial:     uint,
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
	album:      Maybe(Album_ID),
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

Config :: struct {
	prefer_folder_cover_art: bool,
}

CONFIG_DEFAULTS :: Config {
}

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------

Create_Playlist_Event :: struct {
	name: string,
}

Remove_Playlist_Event :: struct {
	id: Playlist_ID,
}

Rename_Playlist_Event :: struct {
	target:   Playlist_ID,
	new_name: string,
}

Remove_Tracks_From_Playlist_Event :: struct {
	target: Playlist_ID,
	tracks: []Track_ID,
}

Add_To_Playlist_Event :: struct {
	tracks: []Track_ID,
	target: Playlist_ID,
}

Track_Add_Info :: struct {
	tags: Track_Tags,
	url:  string,
}

Add_Tracks_Event :: struct {
	tracks: []Track_Add_Info,
}

Remove_Tracks_Event :: struct {
	tracks: []Track_ID,
}

Cover_Art_Add_Info :: struct {
	folder:   string,
	img_path: string,
}

Add_Cover_Art_Event :: struct {
	cover_arts: []Cover_Art_Add_Info,
}

Update_Missing_Tracks_Event :: struct {
	tracks: []Track_ID,
}

Replace_Metadata_Event :: struct {
	replace: string,
	with:    string,
	tracks:  []Track_ID,
	targets: bit_set[Track_Metadata_Replace_Target],
}

Event :: union {
	Create_Playlist_Event,
	Remove_Playlist_Event,
	Rename_Playlist_Event,
	Add_To_Playlist_Event,
	Add_Tracks_Event,
	Remove_Tracks_Event,
	Add_Cover_Art_Event,
	Remove_Tracks_From_Playlist_Event,
	Update_Missing_Tracks_Event,
	Replace_Metadata_Event,
}

// -----------------------------------------------------------------------------
// Main state
// -----------------------------------------------------------------------------

Library :: struct {
	lock:                  sync.RW_Mutex,
	event_queue:           shared.Event_Queue(Event),
	tracks_serial:         uint,
	tracks:                Track_Map,
	shared_strings:        [Shared_String_Type][dynamic]Shared_String,
	tag_arena:             mem.Dynamic_Arena,
	tag_allocator:         mem.Allocator,
	playlists:             Playlist_Map,
	playlists_serial:      uint,
	config:                Config,
	init_config:           Init_Config,
	folder_root:           Folder,
	folder_arena:          mem.Dynamic_Arena,
	folder_allocator:      mem.Allocator,
	folder_serial:         uint,
	folder_cover_art:      map[u64]Folder_Cover_Art, // folder hash -> cover art path
	url_to_track_id:       map[u64]Track_ID, // url hash -> track id
	save_serial:           uint,
	missing_tracks:        [dynamic]Track_ID,
	missing_tracks_serial: uint,

	tracking_allocators: struct {
		tag:         mem.Tracking_Allocator,
		folder_tree: mem.Tracking_Allocator,
	},
}

Init_Config :: struct {
	enable_memory_tracking:  bool,
	prefer_folder_cover_art: bool,
	metadata_db_path:        string,
	playlists_dir:           string,
	wake_proc:               proc(),
}

@(private="file")
_library: Library

init :: proc(config: Init_Config) -> shared.Error {
	l := &_library
	l.init_config = config
	l.config = CONFIG_DEFAULTS

	shared.event_queue_init(&l.event_queue)
	l.event_queue.wake_proc = config.wake_proc

	for &ss in l.shared_strings do reserve(&ss, 128)

	mem.dynamic_arena_init(&l.tag_arena)
	l.tag_allocator = mem.dynamic_arena_allocator(&l.tag_arena)

	mem.dynamic_arena_init(&l.folder_arena)
	l.folder_allocator = mem.dynamic_arena_allocator(&l.folder_arena)

	if config.enable_memory_tracking {
		l.tag_allocator    = shared.track_allocator(l.tag_allocator, &l.tracking_allocators.tag)
		l.folder_allocator = shared.track_allocator(l.folder_allocator, &l.tracking_allocators.folder_tree)
	}

	if config.metadata_db_path != "" do load_db_from_disk(config.metadata_db_path)

	if config.playlists_dir != "" {
		shared.ensure_dir(config.playlists_dir)

		files, _ := os.read_all_directory_by_path(config.playlists_dir, context.allocator)
		defer os.file_info_slice_delete(files, context.allocator)

		for file in files {
			pl := playlist_load(file.fullpath) or_continue
			pl.file = strings.clone(file.fullpath, l.tag_allocator)
			pl.uid = shared.generate_uid()
			_ = hm.dynamic_add(&l.playlists, pl)
		}

		l.playlists_serial += 1
	}

	return nil
}

shutdown :: proc() {
	l := &_library

	delete(l.folder_cover_art)
	delete(l.url_to_track_id)

	mem.tracking_allocator_destroy(&l.tracking_allocators.tag)
	mem.tracking_allocator_destroy(&l.tracking_allocators.folder_tree)

	mem.dynamic_arena_destroy(&l.tag_arena)
	mem.dynamic_arena_destroy(&l.folder_arena)
	hm.dynamic_destroy(&l.tracks)
	for ss in l.shared_strings {
		delete(ss)
	}

	l^ = {}
}

lock_for_read :: proc() {sync.rw_mutex_shared_lock(&_library.lock)}
unlock_for_read :: proc() {sync.rw_mutex_shared_unlock(&_library.lock)}
lock_for_write :: proc() {sync.rw_mutex_lock(&_library.lock)}
unlock_for_write :: proc() {sync.rw_mutex_unlock(&_library.lock)}
@(deferred_out=unlock_for_read)
guard_for_read :: proc() {lock_for_read()}
@(deferred_out=unlock_for_write)
guard_for_write :: proc() {lock_for_write()}

apply_config :: proc(c: Config) {
	_library.config = c
}

// Clones any memory allocated for the event
send_event :: proc(event: Event) {
	l := &_library
	allocator := l.event_queue.event_allocator

	#partial switch v in event {
	case Create_Playlist_Event:
		shared.event_queue_send(&l.event_queue, Create_Playlist_Event {
			name = strings.clone(v.name, allocator)
		})

	case Add_Tracks_Event:
		ev := Add_Tracks_Event {}
		if len(v.tracks) == 0 do break
		ev.tracks = make([]Track_Add_Info, len(v.tracks), allocator)

		for t, i in v.tracks {
			ev.tracks[i].tags = clone_track_tags(t.tags, allocator)
			ev.tracks[i].url = strings.clone(t.url, allocator)
		}

		shared.event_queue_send(&l.event_queue, ev)
	
	case Add_Cover_Art_Event:
		ev := Add_Cover_Art_Event {}
		if len(v.cover_arts) == 0 do break
		ev.cover_arts = make([]Cover_Art_Add_Info, len(v.cover_arts), allocator)

		for cv, i in v.cover_arts {
			ev.cover_arts[i].folder = strings.clone(cv.folder, allocator)
			ev.cover_arts[i].img_path = strings.clone(cv.img_path, allocator)
		}
	
	case Remove_Tracks_Event:
		shared.event_queue_send(&l.event_queue, Remove_Tracks_Event {
			tracks = slice.clone(v.tracks, allocator),
		})
	
	case Add_To_Playlist_Event:
		shared.event_queue_send(&l.event_queue, Add_To_Playlist_Event {
			tracks = slice.clone(v.tracks, allocator),
			target = v.target,
		})

	case Remove_Tracks_From_Playlist_Event:
		shared.event_queue_send(&l.event_queue, Remove_Tracks_From_Playlist_Event {
			tracks = slice.clone(v.tracks, allocator),
			target = v.target,
		})

	case Update_Missing_Tracks_Event:
		shared.event_queue_send(&l.event_queue, Update_Missing_Tracks_Event {
			tracks = slice.clone(v.tracks, allocator),
		})

	case Replace_Metadata_Event:
		shared.event_queue_send(&l.event_queue, Replace_Metadata_Event {
			replace = strings.clone(v.replace, allocator),
			with    = strings.clone(v.with, allocator),
			targets = v.targets,
			tracks  = slice.clone(v.tracks, allocator),
		})

	case: shared.event_queue_send(&l.event_queue, event)
	}
}

wait_for_events :: proc() {
	shared.event_queue_wait(&_library.event_queue)
}

poll_events :: proc() {
	l := &_library

	defer free_all(l.event_queue.event_allocator)

	for event_union in shared.event_queue_get(&l.event_queue) {
		switch event in event_union {
		case Create_Playlist_Event:
			playlist := Playlist {
				name = event.name != "" ? strings.clone(event.name, l.tag_allocator) : "",
				uid  = shared.generate_uid(),
			}

			id, error := hm.dynamic_add(&l.playlists, playlist)

			if error != nil do l.playlists_serial += 1

		case Remove_Playlist_Event:
			playlist := hm.dynamic_get(&l.playlists, event.id) or_break

			if playlist.file != "" {
				os.remove(playlist.file)
			}

			hm.dynamic_remove(&l.playlists, event.id)

			l.playlists_serial += 1

		case Add_To_Playlist_Event:
			any_added: bool

			playlist := hm.dynamic_get(&l.playlists, event.target) or_break

			for track in event.tracks {
				if !slice.contains(playlist.tracks[:], track) {
					append(&playlist.tracks, track)
					any_added = true
				}
			}

			if any_added {
				playlist.serial += 1
				l.playlists_serial += 1
			}

		case Remove_Tracks_From_Playlist_Event:
			playlist := hm.dynamic_get(&l.playlists, event.target) or_break
			any_removed := false

			for remove_id in event.tracks {
				i := slice.linear_search(playlist.tracks[:], remove_id) or_continue
				any_removed = true
				ordered_remove(&playlist.tracks, i)
			}

			if any_removed {
				l.playlists_serial += 1
				playlist.serial += 1
			}

		case Rename_Playlist_Event:
			playlist := hm.dynamic_get(&l.playlists, event.target) or_break
			playlist.name = strings.clone(event.new_name, l.tag_allocator)
			playlist.serial += 1

		case Add_Tracks_Event:
			for ti in event.tracks {
				_add_track(ti.tags, ti.url)
			}

		case Remove_Tracks_Event:
			for t in event.tracks {
				_remove_track(t)
			}

		case Add_Cover_Art_Event:
			for cv in event.cover_arts {
				_add_cover_art(cv.folder, cv.img_path)
			}

		case Update_Missing_Tracks_Event:
			clear(&l.missing_tracks)

			for track in event.tracks {
				if !slice.contains(l.missing_tracks[:], track) {
					append(&l.missing_tracks, track)
				}
			}

			l.missing_tracks_serial += 1

		case Replace_Metadata_Event:
			replace_track_metadata(
				event.tracks[:], event.targets, event.replace, event.with, l.tag_allocator
			)
			l.tracks_serial += 1
		}
	}

	if l.folder_serial != l.tracks_serial {
		l.folder_serial = l.tracks_serial
		shared.TIME_SCOPE("Build folder tree")
		free_all(l.folder_allocator)
		build_folder_tree(&l.folder_root, l.folder_allocator)
	}

	if l.init_config.metadata_db_path != "" && l.save_serial != l.tracks_serial {
		l.save_serial = l.tracks_serial
		save_db_to_disk(l.init_config.metadata_db_path)
	}

	if l.init_config.playlists_dir != "" {
		iter := make_playlist_iterator()

		for playlist in iterate_playlists(&iter) {
			if playlist.save_serial != playlist.serial {
				playlist_save_to_dir(playlist, l.init_config.playlists_dir)
				playlist.save_serial = playlist.serial
			}
		}
	}
}

get_playlists_serial :: proc() -> uint {return _library.playlists_serial}
get_tracks_serial :: proc() -> uint {return _library.tracks_serial}
get_root_folder :: proc() -> ^Folder {return &_library.folder_root}
get_folder_tree_serial :: proc() -> uint {return _library.folder_serial}
get_folder_cover_art_map :: proc() -> map[u64]Folder_Cover_Art {return _library.folder_cover_art}
get_missing_tracks :: proc() -> []Track_ID {return _library.missing_tracks[:]}
get_missing_tracks_serial :: proc() -> uint {return _library.missing_tracks_serial}

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

@private
_add_track :: proc(tags: Track_Tags, url: string) -> (id: Track_ID, ok: bool) {
	track: Track

	l := &_library
	url_hash := hash.fnv64a(transmute([]u8) url)

	if existing, exists := l.url_to_track_id[url_hash]; exists {
		id = existing
		ok = true
		return
	}

	split_shared_strings :: proc(s: string, type: Shared_String_Type) -> []Shared_String_ID {
		l := &_library

		if s == "" do return nil

		parts := strings.split(s, ",", context.allocator)
		
		if len(parts) == 0 do return nil
		defer delete(parts)

		output := make([]Shared_String_ID, len(parts), l.tag_allocator)
		for &p, i in parts {
			output[i] = _add_shared_string(type, strings.trim_space(p))
		}

		return output
	}

	if tags.album != "" {
		track.album = auto_cast _add_shared_string(.Album, tags.album)
	}
	track.artists    = split_shared_strings(tags.artist, .Artist)
	track.genres     = split_shared_strings(tags.genre, .Genre)
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
	track.artists    = slice.unique(track.artists)
	track.genres     = slice.unique(track.genres)

	assert(track.title != "")
	assert(track.url != "")

	id = hm.dynamic_add(&l.tracks, track)
	ok = true
	
	l.tracks_serial += 1
	l.url_to_track_id[url_hash] = id

	return
}

@private
_remove_track :: proc(id: Track_ID) {
	// We don't worry about freeing up track memory here because
	// 99% of the time tracks are only being added, not removed.
	// We are only leaking a few bytes here anyway.

	l := &_library

	hm.dynamic_remove(&l.tracks, id)

	l.tracks_serial += 1
}

@private
_add_cover_art :: proc(folder: string, img: string) {
	l := &_library
	cleaned, _ := filepath.clean(folder)
	defer delete(cleaned)

	folder_hash := hash.fnv64a(transmute([]byte) folder)

	l.folder_cover_art[folder_hash] = {
		folder = strings.clone(folder, l.tag_allocator),
		image  = strings.clone(img, l.tag_allocator),
	}
}

/*remove_all_missing_tracks :: proc() -> int {
	l := &_library
	iter := make_track_iterator()
	removed_count: int

	for track in iterate_tracks(&iter) {
		strings.starts_with(track.url, "file://") or_continue
		path := strings.trim_prefix(track.url, "file://")
		if !os.exists(path) {
			_remove_track(track.handle)
			removed_count += 1
		}
	}

	if removed_count > 0 do _library.tracks_serial += 1

	return removed_count
}*/

/*scan_for_missing_tracks :: proc() {
	l := &_library
	iter := make_track_iterator()
	input := make_dynamic_array_len_cap([dynamic]Missing_Track_Scan_Input, 0, get_track_count())
	defer delete(input)

	for track in iterate_tracks(&iter) {
		if !strings.starts_with(track.url, "file://") do continue

		append(&input, Missing_Track_Scan_Input {
			track_id = track.handle,
			path     = strings.trim_prefix(track.url, "file://"),
		})
	}

	{
		guard_write()
		clear(&l.missing_tracks)
	}

	shared.worker_send_input(&l.missing_track_scanner, input[:])
}*/

/*get_missing_tracks :: proc(allocator: mem.Allocator) -> []Track_ID {
	l := &_library
	ids := make([]Track_ID, len(l.missing_tracks), allocator)

	for mt, i in l.missing_tracks {
		ids[i] = mt.track_id
	}

	return ids
}*/

get_track :: proc(id: Track_ID) -> (track: Track, found: bool) {
	l := &_library
	ptr := hm.dynamic_get(&l.tracks, id) or_return
	track = ptr^
	found = true
	return
}

@private
get_track_ptr :: proc(id: Track_ID) -> (track: ^Track, ok: bool) {
	return hm.dynamic_get(&_library.tracks, id)
}

get_tracks :: proc(ids: []Track_ID, allocator: mem.Allocator) -> []Track {
	l := &_library

	count: int
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

get_track_count :: proc() -> int {
	return int(hm.dynamic_len(_library.tracks))
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

get_playlist :: proc(id: Playlist_ID) -> (pl: Playlist, ok: bool) {
	ptr := hm.dynamic_get(&_library.playlists, id) or_return
	return ptr^, true
}

make_playlist_iterator :: proc() -> Playlist_Iterator {
	return hm.dynamic_iterator_make(&_library.playlists)
}

iterate_playlists :: proc(iter: ^Playlist_Iterator) -> (pl: ^Playlist, ok: bool) {
	ptr, _ := hm.dynamic_iterate(iter) or_return
	return ptr, true
}

create_playlist :: proc(name: string) -> bool {
	l := &_library
	send_event(Create_Playlist_Event {name = name})
	return true
}

remove_playlist :: proc(id: Playlist_ID) -> bool {
	send_event(Remove_Playlist_Event {id = id})
	return true
}

rename_playlist :: proc(id: Playlist_ID, new_name: string) -> bool {
	send_event(Rename_Playlist_Event {target = id, new_name = new_name})
	return true
}

add_to_playlist :: proc(id: Playlist_ID, tracks: []Track_ID) -> bool {
	send_event(Add_To_Playlist_Event {target = id, tracks = tracks})
	return true
}

remove_from_playlist :: proc(id: Playlist_ID, tracks: []Track_ID) -> bool {
	send_event(Remove_Tracks_From_Playlist_Event{target = id, tracks = tracks})
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

// Maybe store comments permanently in the library?
get_track_comment :: proc(track_id: Track_ID, allocator: mem.Allocator) -> (comment: string, ok: bool) {
	track := get_track(track_id) or_return
	if !strings.starts_with(track.url, "file://") do return
	return read_comment(strings.trim_prefix(track.url, "file://"), allocator)
}

@private
_add_shared_string :: proc(type: Shared_String_Type, name: string) -> i16 {
	l := &_library

	for &s, i in l.shared_strings[type] {
		if s.name == name {
			s.serial += 1
			return auto_cast i
		}
	}

	s := Shared_String {
		name       = strings.clone(name, l.tag_allocator),
		lower_name = strings.to_lower(name, l.tag_allocator),
		uid        = shared.generate_uid(),
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

get_shared_string_uid :: proc(type: Shared_String_Type, id: Shared_String_ID) -> shared.UID {
	return _library.shared_strings[type][id].uid
}

get_shared_string_serial :: proc(type: Shared_String_Type, id: Shared_String_ID) -> uint {
	return _library.shared_strings[type][id].serial
}

get_shared_strings :: proc(type: Shared_String_Type, ids: []Shared_String_ID, out: []string) {
	assert(len(ids) == len(out))

	for id, i in ids {
		out[i] = _library.shared_strings[type][id].name
	}
}

get_all_shared_strings :: proc(type: Shared_String_Type, allocator: mem.Allocator) -> []Shared_String {
	return slice.clone(_library.shared_strings[type][:], allocator)
}

url_to_filepath :: proc(url: string) -> (string, bool) {
	if !strings.starts_with(url, "file://") do return "", false
	return strings.trim_prefix(url, "file://"), true
}

track_has_artist :: proc(t: Track, id: Shared_String_ID) -> bool {
	for a in t.artists do if a == id do return true
	return false
}

track_has_genre :: proc(t: Track, id: Shared_String_ID) -> bool {
	for g in t.genres do if g == id do return true
	return false
}

get_tracks_with_shared_string :: proc(type: Shared_String_Type, id: Shared_String_ID, out: ^[dynamic]Track_ID) -> int {
	l := &_library
	count := 0

	iter := make_track_iterator()

	switch type {
	case .Artist:
		for t in iterate_tracks(&iter) {
			if track_has_artist(t^, id) && !slice.contains(out[:], t.handle) {
				append(out, t.handle)
				count += 1
			}
		}
	case .Genre:
		for t in iterate_tracks(&iter) {
			if track_has_genre(t^, id) && !slice.contains(out[:], t.handle) {
				append(out, t.handle)
				count += 1
			}
		}
	case .Album:
		for t in iterate_tracks(&iter) {
			if t.album != nil && t.album.? == id && !slice.contains(out[:], t.handle) {
				append(out, t.handle)
				count += 1
			}
		}
	}

	return count
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

	_add_track(track, "file://C:/Music/Computer_Music.mp3")

	dump_tracks()
}
