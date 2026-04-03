package main

import "src:bindings/taglib"
import "core:os"
import "core:slice"
import "core:sort"
import "core:time"
import "core:strings"
import "core:log"
import "core:path/filepath"
import hm "core:container/handle_map"
import "core:mem"

// High-level storage of track data
Track_Data :: struct {
	url: string,
	protocol: Track_Protocol,

	artist,
	album,
	genre,
	title: string,

	format: Audio_File_Format,
	flags: bit_set[Track_Flag; u8],

	duration_seconds: i32,
	track_no: i16,
	channels: i16,
	samplerate: i32,
	release_year: i32,
	bitrate_kbps: i32,

	file_size: int,

	file_date,
	date_added: time.Time,
}

// Raw storage of track data in the server
Track :: struct {
	handle: Track_ID,
	artist: Artist_ID,
	album: Album_ID,
	genre: Genre_ID,
	url: string,
	title: string,
	format: Audio_File_Format,
	protocol: Track_Protocol,
	flags: bit_set[Track_Flag; u8],
	duration_seconds: i32,
	release_year: i32,
	samplerate: i32,
	track_no: i16,
	channels: i16,
	bitrate_kbps: i16,
	file_size: i64,
	file_date, date_added: time.Time,
}

Track_Group_Entry :: struct {
	name: string,
	name_hash: u32,
	// Index of the entry in the sorted entry array.
	// Use to compare tracks
	sort_index: int,
	serial: uint,
	uid: UID,
	tracks: [dynamic]Track_ID,
}

Track_Group_Entry_Ptr :: #soa^#soa[dynamic]Track_Group_Entry

// Entries never get removed or rearranged for the duration of the program
// so it is safe to store an index into the entries array
Track_Group :: struct {
	name: string,
	arena: mem.Dynamic_Arena,
	entries: #soa[dynamic]Track_Group_Entry,
	sorted_indices: [dynamic]int,
	serial: uint,
}

Library :: struct {
	allocator_map: Allocator_Map,
	allocators: struct {
		tracks: mem.Allocator,
		// Freed after event handling
		temp: mem.Allocator,
	},

	tracks: hm.Dynamic_Handle_Map(Track, Track_ID),
	url_hash_map: map[u64]Track_ID,

	artists: Track_Group,
	albums: Track_Group,
	genres: Track_Group,
	
	folder_cover_art: map[u64]string,
	
	// Serial of library when groups were sorted
	group_sort_serial: uint,
	serial: uint,
}

library_init :: proc(l: ^Library) {
	l.allocators.tracks = allocator_map_add_dynamic_arena(&l.allocator_map, "tracks")
	l.allocators.temp = allocator_map_add_dynamic_arena(&l.allocator_map, "temp")
	track_group_init(&l.artists)
	track_group_init(&l.albums)
	track_group_init(&l.genres)
	l.artists.name = "Artist"
	l.albums.name = "Album"
	l.genres.name = "Genre"
	l.serial = 1
}

library_destroy :: proc(l: ^Library) {
	hm.dynamic_destroy(&l.tracks)
	delete(l.folder_cover_art)
	delete(l.url_hash_map)
}

library_update :: proc(l: ^Library) {
	if l.group_sort_serial != l.serial {
		log.debug("Sorting track groups...")
		track_group_pseudo_sort(&l.albums)
		track_group_pseudo_sort(&l.artists)
		track_group_pseudo_sort(&l.genres)
		l.group_sort_serial = l.serial
	}
}

library_add_track :: proc(
	l: ^Library, data: Track_Data, update_existing := false
) -> (id: Track_ID, ok: bool) {
	hash := hash_track_url(data.url)
	if hash == 0 do return {}, false

	/*if existing_handle, exists := sv.track_url_hash_map[hash]; exists {
		if update_existing {
			if ptr, found := hm.get(&sv.tracks, existing_handle); found {
				ptr^ = stored
				return existing_handle, true
			}
			else {
				delete_key(&sv.track_url_hash_map, hash)
			}
		}
		else if hm.is_valid(&sv.tracks, existing_handle) {
			return existing_handle, true
		}
	}*/

	if extisting_handle, exists := l.url_hash_map[hash]; exists  {
		return extisting_handle, true
	}

	if data.protocol == .File {
		dir := filepath.dir(data.url)
		defer delete(dir)

		library_scan_directory_for_cover_art(l, dir)
	}

	handle, error := hm.add(&l.tracks, Track{})
	
	if error != nil {
		log.error(error)
		return {}, false
	}

	ptr := hm.get(&l.tracks, handle) or_return
	ptr.album            = library_get_or_add_album(l, data.album, handle)
	ptr.artist           = library_get_or_add_artist(l, data.artist, handle)
	ptr.genre            = library_get_or_add_genre(l, data.genre, handle)
	ptr.bitrate_kbps     = auto_cast data.bitrate_kbps
	ptr.channels         = auto_cast data.channels
	ptr.duration_seconds = auto_cast data.duration_seconds
	ptr.file_size        = auto_cast data.file_size
	ptr.flags            = auto_cast data.flags
	ptr.format           = data.format
	ptr.samplerate       = auto_cast data.samplerate
	ptr.title            = strings.clone(data.title, l.allocators.tracks)
	ptr.url              = strings.clone(data.url, l.allocators.tracks)
	ptr.date_added       = time.now()
	ptr.file_date        = data.file_date
	ptr.protocol         = data.protocol

	l.url_hash_map[hash] = handle
	l.serial += 1


	return handle, true
}

library_add_track_from_file :: proc(l: ^Library, path: string) -> (track_id: Track_ID, ok: bool) {
	track := read_audio_file_metadata(path, l.allocators.temp) or_return
	return library_add_track(l, track)
}

library_get_all_tracks :: proc(l: ^Library, allocator: mem.Allocator) -> []Track_ID {
	out := make([]Track_ID, hm.len(l.tracks), allocator)
	it := hm.iterator_make(&l.tracks)
	i := 0
	for track, _ in hm.iterate(&it) {
		out[i] = track.handle
		i += 1
	}

	return out[:i]
}

library_get_artist_name :: proc(l: Library, id: Artist_ID) -> string {
	return l.artists.entries[id].name
}

library_get_album_name :: proc(l: Library, id: Album_ID) -> string {
	return l.albums.entries[id].name
}

library_get_genre_name :: proc(l: Library, id: Genre_ID) -> string {
	return l.genres.entries[id].name
}

library_save :: proc(l: ^Library, path: string) -> bool {
	TIME_SCOPE("Save library", path)

	track_db_save(l, path)

	// @TODO: Save folder cover art

	return true
}

library_load :: proc(l: ^Library, path: string) -> bool {
	TIME_SCOPE("Load library", path)

	track_db_load(l, path)

	track_group_pseudo_sort(&l.albums)
	track_group_pseudo_sort(&l.artists)
	track_group_pseudo_sort(&l.genres)

	// @TODO: Load folder cover art

	return true
}


library_get_track :: proc(l: ^Library, handle: Track_ID) -> (track: ^Track, found: bool) {
	return hm.get(&l.tracks, handle)
}

// -----------------------------------------------------------------------------
// Track groups
// -----------------------------------------------------------------------------
track_group_get_entry :: proc(tg: ^Track_Group, hash: u32) -> (index: int, found: bool) {
	for h, i in tg.entries.name_hash[:len(tg.entries)] {
		if h == hash do return i, true
	}
	return
}

track_group_init :: proc(tg: ^Track_Group) {
	mem.dynamic_arena_init(&tg.arena)
	append(&tg.entries, Track_Group_Entry {
		name = "",
		name_hash = hash_string_32(""),
	})
}

track_group_add_track :: proc(
	tg: ^Track_Group, str: string, track_id: Track_ID
) -> int {
	hash := hash_string_32(str)
	index := track_group_get_entry(tg, hash) or_else -1
	allocator := mem.dynamic_arena_allocator(&tg.arena)

	if index == -1 {
		index = len(tg.entries)
		append(&tg.entries, Track_Group_Entry{
			name = strings.clone(str, allocator),
			name_hash = hash_string_32(str),
			uid = generate_uid(),
		})
	}

	entry := &tg.entries[index]
	entry.serial += 1
	append(&entry.tracks, track_id)

	tg.serial += 1

	return index
}

track_group_remove_track :: proc(tg: ^Track_Group, entry_index: int, id: Track_ID) -> bool {
	entry := &tg.entries[entry_index]
	index := slice.linear_search(entry.tracks[:], id) or_return
	ordered_remove(&entry.tracks, index)

	return true
}

// Broken, but keep for future
track_group_pseudo_sort :: proc(tg: ^Track_Group) {
	resize(&tg.sorted_indices, len(tg.entries))

	for &e, i in tg.entries {
		tg.sorted_indices[i] = i
	}

	iface := sort.Interface {
		collection = tg,
		len = proc(it: sort.Interface) -> int {
			tg := cast(^Track_Group) it.collection
			return len(tg.entries)
		},
		swap = proc(it: sort.Interface, a, b: int) {
			tg := cast(^Track_Group) it.collection
			tg.sorted_indices[a], tg.sorted_indices[b] = tg.sorted_indices[b], tg.sorted_indices[a]
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			tg := cast(^Track_Group) it.collection
			A := tg.sorted_indices[a]
			B := tg.sorted_indices[b]
			return strings.compare(tg.entries[A].name, tg.entries[B].name) < 0
		}
	}

	sort.sort(iface)

	log.debug(tg.sorted_indices[:])
}

library_get_or_add_artist :: proc(l: ^Library, name: string, track_id: Track_ID) -> Artist_ID {
	return auto_cast track_group_add_track(&l.artists, name, track_id)
}

library_get_or_add_album :: proc(l: ^Library, name: string, track_id: Track_ID) -> Album_ID {
	return auto_cast track_group_add_track(&l.albums, name, track_id)
}

library_get_or_add_genre :: proc(l: ^Library, name: string, track_id: Track_ID) -> Genre_ID {
	return auto_cast track_group_add_track(&l.genres, name, track_id)
}

find_track_thumbnail :: proc(
	l: ^Library, track_id: Track_ID, allocator: mem.Allocator
) -> (data: []byte, mime_type: string, found: bool) {
	track := library_get_track(l, track_id) or_return
	file := taglib_open(track.url)
	if file == nil do return
	defer taglib.file_free(file)

	// Try find in folder cover arts
	if track.protocol == .File {
		dir := filepath.dir(track.url, context.allocator)
		defer delete(dir)

		hash := hash_string_64(dir)
		path := l.folder_cover_art[hash] or_else ""
		if path != "" {
			read_error: os.Error
			data, read_error = os.read_entire_file_from_path(path, allocator)
			if read_error != nil {
				log.error("Error trying to read folder cover art:", read_error)
			}
			else {
				mime_type = strings.clone(guess_file_mime_type(path), allocator)
				found = true
				return
			}
		}
	}

	picture_data: taglib.Complex_Property_Picture_Data
	picture_prop := taglib.complex_property_get(file, "PICTURE")
	if picture_prop == nil do return
	taglib.picture_from_complex_property(picture_prop, &picture_data)
	defer taglib.complex_property_free(picture_prop)

	data = slice.clone(picture_data.data[:picture_data.size], allocator)
	mime_type = strings.clone(string(picture_data.mimeType), allocator)
	found = true

	return
}

library_scan_directory_for_cover_art :: proc(l: ^Library, dir: string) {
	hash := hash_string_64(dir)
	if hash in l.folder_cover_art do return

	files, error := os.read_all_directory_by_path(dir, context.allocator)
	if error != nil {
		log.error(error)
		return
	}
	defer os.file_info_slice_delete(files, context.allocator)

	for file in files {
		if file_is_type(file.fullpath, .Image) {
			log.debug("Adding cover art", file.fullpath, "for folder", dir)
			l.folder_cover_art[hash] = strings.clone(file.fullpath, l.allocators.tracks)
			return
		}
	}

	l.folder_cover_art[hash] = ""
}

Track_List_Totals :: struct {
	duration: i64,
	file_size: i64,
}

calculate_track_totals :: proc(l: ^Library, tracks: []Track_ID) -> Track_List_Totals {
	t: Track_List_Totals

	for track_id in tracks {
		track := library_get_track(l, track_id) or_continue
		t.duration += auto_cast track.duration_seconds
		t.file_size += track.file_size
	}

	return t
}
