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

Track_ID :: distinct u32

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
	url:              string,
	title:            string,
	file_date,        date_added: time.Time,
	file_size:        i64,
	id:               Track_ID,
	duration_seconds: i32,
	release_year:     i32,
	samplerate:       i32,
	artist:           Artist_ID,
	album:            Album_ID,
	genre:            Genre_ID,
	track_no:         i16,
	channels:         i16,
	bitrate_kbps:     i16,
	format:           Audio_File_Format,
	flags:            bit_set[Track_Flag; u8],
	protocol:         Track_Protocol,
}

Track_Group :: struct {
	name: string,
	lower_case_name: string,
	name_hash: u32,
	// Index of the entry in the sorted entry array.
	// Use to compare tracks
	sort_index: int,
	serial: uint,
	uid: UID,
	tracks: [dynamic]Track_ID,
}

Track_Group_Ptr :: #soa^#soa[dynamic]Track_Group

// Entries never get removed or rearranged for the duration of the program
// so it is safe to store an index into the entries array
Track_Group_Set :: struct {
	name: string,
	arena: mem.Dynamic_Arena,
	entries: #soa[dynamic]Track_Group,
	sorted_indices: [dynamic]int,
	serial: uint,
}

Library :: struct {
	allocator_map: Allocator_Map,
	allocators: struct {
		track_data: mem.Allocator,
		track_map: mem.Allocator,
		// Freed after event handling
		temp: mem.Allocator,
	},

	last_track_id: Track_ID,
	tracks: map[Track_ID]Track,
	url_hash_map: map[u64]Track_ID,

	artists: Track_Group_Set,
	albums: Track_Group_Set,
	genres: Track_Group_Set,

	playlists: hm.Static_Handle_Map(256, Playlist, Playlist_Handle),
	playlists_serial: uint,
	
	folder_cover_art: map[u64]string,
	
	// Serial of library when groups were sorted
	group_sort_serial: uint,
	serial: uint,
}

library_init :: proc(l: ^Library) {
	log.debug("size_of(Track) =", size_of(Track))

	l.allocators.track_data = allocator_map_add_dynamic_arena(&l.allocator_map, "track_data")
	l.allocators.track_map = allocator_map_add_heap(&l.allocator_map, "track_map")
	l.allocators.temp = allocator_map_add_dynamic_arena(&l.allocator_map, "temp")
	track_group_init(&l.artists)
	track_group_init(&l.albums)
	track_group_init(&l.genres)
	l.artists.name = "Artist"
	l.albums.name = "Album"
	l.genres.name = "Genre"
	l.serial = 1

	l.tracks = make_map_cap(map[Track_ID]Track, 4096, l.allocators.track_map)
	l.url_hash_map = make_map_cap(map[u64]Track_ID, 4096, l.allocators.track_map)
}

library_destroy :: proc(l: ^Library) {
	delete(l.tracks)
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
	l: ^Library, data: Track_Data,
	update_existing := false,
	overwrite_id: Maybe(Track_ID) = nil,
) -> (id: Track_ID, error: Error) {
	hash := hash_track_url(data.url)
	if hash == 0 do return {}, false

	if existing_id, exists := l.url_hash_map[hash]; exists  {
		if !update_existing do return existing_id, nil
		id = existing_id
	}
	else {
		l.last_track_id += 1
		id = l.last_track_id
		l.tracks[id] = Track{}
	}

	if data.protocol == .File && data.url != "" {
		dir := filepath.dir(data.url)
		defer delete(dir)

		library_scan_directory_for_cover_art(l, dir)
	}

	library_add_or_update_track(l, id, data) or_return

	return
}

// Adds or overwrites track with given ID
library_add_or_update_track :: proc(
	l: ^Library, id: Track_ID, data: Track_Data,
) -> Error {
	hash := hash_track_url(data.url)
	if hash == 0 do return .InvalidInput

	track: Track

	track.url              = strings.clone(data.url, l.allocators.track_data)
	track.title            = strings.clone(data.title, l.allocators.track_data)
	track.file_date        = data.file_date
	track.file_size        = auto_cast data.file_size
	track.id               = id
	track.duration_seconds = auto_cast data.duration_seconds
	track.release_year     = data.release_year
	track.samplerate       = auto_cast data.samplerate
	track.track_no         = data.track_no
	track.channels         = auto_cast data.channels
	track.bitrate_kbps     = auto_cast data.bitrate_kbps
	track.format           = data.format
	track.flags            = auto_cast data.flags
	track.protocol         = data.protocol
	track.artist           = library_get_or_add_artist(l, data.artist, id)
	track.album            = library_get_or_add_album(l, data.album, id)
	track.genre            = library_get_or_add_genre(l, data.genre, id)
	track.date_added       = time.now()
	
	l.tracks[id] = track
	l.url_hash_map[hash] = id
	l.serial += 1

	return nil
}

library_remove_tracks :: proc(l: ^Library, tracks: []Track_ID) {
	for track_id in tracks {
		track := l.tracks[track_id] or_continue
		url_hash := hash_track_url(track.url)

		track_group_remove_track(&l.artists, auto_cast track.artist, track_id)
		track_group_remove_track(&l.genres, auto_cast track.album, track_id)
		track_group_remove_track(&l.albums, auto_cast track.genre, track_id)

		delete_key(&l.tracks, track_id)
		delete_key(&l.url_hash_map, url_hash)
	}

	l.serial += 1
}

library_get_missing_tracks :: proc(l: Library, allocator: mem.Allocator) -> []Track_ID {
	tracks := make_dynamic_array_len_cap([dynamic]Track_ID, 0, len(l.tracks), allocator)

	for track_id, track in l.tracks {
		if !os.exists(track.url) do append(&tracks, track_id)
	}

	return tracks[:]
}

library_add_track_from_file :: proc(l: ^Library, path: string) -> (track_id: Track_ID, error: Error) {
	track := read_audio_file_metadata(path, l.allocators.temp) or_return
	return library_add_track(l, track)
}

library_update_track_from_file :: proc(l: ^Library, path: string, track_id: Track_ID) -> Error {
	data := read_audio_file_metadata(path, l.allocators.temp) or_return
	library_add_or_update_track(l, track_id, data)
	return nil
}

library_get_all_tracks :: proc(l: Library, allocator: mem.Allocator) -> (keys: []Track_ID, error: Error) {
	keys = slice.map_keys(l.tracks, allocator) or_return
	return
}

library_get_artist_name :: proc(l: Library, id: Artist_ID) -> string {return l.artists.entries[id].name}
library_get_album_name :: proc(l: Library, id: Album_ID) -> string {return l.albums.entries[id].name}
library_get_genre_name :: proc(l: Library, id: Genre_ID) -> string {return l.genres.entries[id].name}

library_get_artist_name_lower :: proc(l: Library, id: Artist_ID) -> string {return l.artists.entries[id].lower_case_name}
library_get_album_name_lower :: proc(l: Library, id: Album_ID) -> string {return l.albums.entries[id].lower_case_name}
library_get_genre_name_lower :: proc(l: Library, id: Genre_ID) -> string {return l.genres.entries[id].lower_case_name}

library_save :: proc(l: Library, path: string) -> Error {
	TIME_SCOPE("Save library", path)
	return track_db_save(l, path)
}

library_load :: proc(l: ^Library, path: string) -> Error {
	TIME_SCOPE("Load library", path)

	track_db_load(l, path) or_return

	track_group_pseudo_sort(&l.albums)
	track_group_pseudo_sort(&l.artists)
	track_group_pseudo_sort(&l.genres)

	return nil
}


library_get_track :: proc(l: Library, id: Track_ID) -> (track: Track, found: bool) {
	return l.tracks[id]
}


// -----------------------------------------------------------------------------
// Playlist management
// -----------------------------------------------------------------------------

Cant_Add_Playlist_Reason :: enum {
	None,
	NameExists,
	NameEmpty,
}

library_can_add_playlist :: proc(l: ^Library, name: string) -> Cant_Add_Playlist_Reason {
	if name == "" do return .NameEmpty
	it := hm.iterator_make(&l.playlists)
	for playlist, _ in hm.iterate(&it) {
		if name == playlist.name do return .NameExists
	}

	return .None
}

library_add_playlist :: proc(l: ^Library, name: string) -> (handle: Playlist_Handle, ok: bool) {
	pl := Playlist {
		uid = generate_uid(),
		name_cstring = strings.clone_to_cstring(name),
		serial = 1,
	}
	pl.name = string(pl.name_cstring)

	handle = hm.add(&l.playlists, pl) or_return
	l.playlists_serial += 1
	
	ok = true
	return
}

library_get_playlist :: proc(l: ^Library, handle: Playlist_Handle) -> (playlist: ^Playlist, found: bool) {
	return hm.get(&l.playlists, handle)
}


// -----------------------------------------------------------------------------
// Track groups
// -----------------------------------------------------------------------------
track_group_get_entry :: proc(tg: ^Track_Group_Set, hash: u32) -> (index: int, found: bool) {
	count := len(tg.entries)
	for h, i in tg.entries.name_hash[:count] {
		if h == hash do return i, true
	}
	return
}

track_group_init :: proc(tg: ^Track_Group_Set) {
	mem.dynamic_arena_init(&tg.arena)
	reserve(&tg.entries, 512)
	append(&tg.entries, Track_Group {
		name = "",
		name_hash = stable_hash_string_32(""),
	})
}

track_group_add_track :: proc(
	tg: ^Track_Group_Set, str: string, track_id: Track_ID
) -> int {
	hash := stable_hash_string_32(str)
	index := track_group_get_entry(tg, hash) or_else -1
	allocator := mem.dynamic_arena_allocator(&tg.arena)

	if index == -1 {
		index = len(tg.entries)
		append(&tg.entries, Track_Group{
			name = strings.clone(str, allocator),
			lower_case_name = strings.to_lower(str, allocator),
			name_hash = stable_hash_string_32(str),
			uid = generate_uid(),
		})

		reserve(&tg.entries[index].tracks, 64)
	}

	entry := &tg.entries[index]
	entry.serial += 1
	append(&entry.tracks, track_id)

	tg.serial += 1

	return index
}

track_group_remove_track :: proc(tg: ^Track_Group_Set, entry_index: int, id: Track_ID) -> bool {
	entry := &tg.entries[entry_index]
	index := slice.linear_search(entry.tracks[:], id) or_return
	ordered_remove(&entry.tracks, index)
	entry.serial += 1

	return true
}

// Broken, but keep for future
track_group_pseudo_sort :: proc(tg: ^Track_Group_Set) {
	resize(&tg.sorted_indices, len(tg.entries))

	for _, i in tg.entries {
		tg.sorted_indices[i] = i
	}

	iface := sort.Interface {
		collection = tg,
		len = proc(it: sort.Interface) -> int {
			tg := cast(^Track_Group_Set) it.collection
			return len(tg.entries)
		},
		swap = proc(it: sort.Interface, a, b: int) {
			tg := cast(^Track_Group_Set) it.collection
			tg.sorted_indices[a], tg.sorted_indices[b] = tg.sorted_indices[b], tg.sorted_indices[a]
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			tg := cast(^Track_Group_Set) it.collection
			A := tg.sorted_indices[a]
			B := tg.sorted_indices[b]
			return strings.compare(tg.entries[A].name, tg.entries[B].name) < 0
		}
	}

	sort.sort(iface)
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
	l: Library, track_id: Track_ID, allocator: mem.Allocator
) -> (data: []byte, mime_type: string, found: bool) {
	track := library_get_track(l, track_id) or_return
	file := taglib_open(track.url)
	if file == nil do return
	defer taglib.file_free(file)

	// Try find in folder cover arts
	if track.protocol == .File {
		dir := filepath.dir(track.url, context.allocator)
		defer delete(dir)

		hash := stable_hash_string_64(dir)
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
	hash := stable_hash_string_64(dir)
	if hash in l.folder_cover_art do return
	log.debug("Scanning directory", dir, "for cover art")

	files, error := os.read_all_directory_by_path(dir, context.allocator)
	if error != nil {
		log.error(error)
		return
	}
	defer os.file_info_slice_delete(files, context.allocator)

	for file in files {
		if file_is_type(file.fullpath, .Image) {
			log.debug("Adding cover art", file.fullpath, "for folder", dir)
			l.folder_cover_art[hash] = strings.clone(file.fullpath, l.allocators.track_data)
			return
		}
	}

	l.folder_cover_art[hash] = ""
}

Track_List_Totals :: struct {
	duration: i64,
	file_size: i64,
}

calculate_track_totals :: proc(l: Library, tracks: []Track_ID) -> Track_List_Totals {
	t: Track_List_Totals

	for track_id in tracks {
		track := library_get_track(l, track_id) or_continue
		t.duration += auto_cast track.duration_seconds
		t.file_size += track.file_size
	}

	return t
}

Track_Filter_Metric :: enum {
	Artist,
	Album,
	Genre,
	Title,
	Url,
	Format,
}

Track_Filter_Spec :: struct {
	metrics: bit_set[Track_Filter_Metric],
	filter_string: string,
}

filter_track :: proc(l: Library, t: Track, filter: string, metrics: bit_set[Track_Filter_Metric], temp_allocator: mem.Allocator) -> bool {
	if .Artist in metrics {
		if strings.contains(library_get_artist_name_lower(l, t.artist), filter) do return true
	}

	if .Album in metrics {
		if strings.contains(library_get_album_name_lower(l, t.album), filter) do return true
	}

	if .Genre in metrics {
		if strings.contains(library_get_genre_name_lower(l, t.genre), filter) do return true
	}

	if .Title in metrics {
		lower := strings.to_lower(t.title, temp_allocator)
		if strings.contains(lower, filter) do return true
	}

	if .Url in metrics {
		lower := strings.to_lower(t.url, temp_allocator)
		if strings.contains(lower, filter) do return true
	}

	if .Format in metrics {
		lower := strings.to_lower(AUDIO_FILE_FORMAT_DISPLAY_NAMES[t.format].short, temp_allocator)
		if strings.contains(lower, filter) do return true
		lower = strings.to_lower(AUDIO_FILE_FORMAT_DISPLAY_NAMES[t.format].long, temp_allocator)
		if strings.contains(lower, filter) do return true
	}

	return false
}

filter_tracks :: proc(l: Library, output: ^[dynamic]Track_ID, input: []Track_ID, spec: Track_Filter_Spec) {
	TIME_SCOPE("Filter", len(input), "tracks with metrics", spec.metrics)

	arena: mem.Dynamic_Arena

	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	temp_allocator := mem.dynamic_arena_allocator(&arena)

	lower_filter := strings.to_lower(spec.filter_string, temp_allocator)

	for track_id in input {
		track := library_get_track(l, track_id) or_continue

		if filter_track(l, track, lower_filter, spec.metrics, temp_allocator) {
			append(output, track_id)
		}
	}
}

filter_track_groups :: proc(l: Library, output: ^#soa[dynamic]Track_Group, tg: Track_Group_Set, filter: string) {
	lower_filter := strings.to_lower(filter, l.allocators.temp)
	defer delete(lower_filter)

	for entry in tg.entries {
		if strings.contains(entry.lower_case_name, lower_filter) {
			append(output, entry)
		}
	}
}

// -----------------------------------------------------------------------------
// Radio
// -----------------------------------------------------------------------------

library_build_radio :: proc(l: Library, main_track_id: Track_ID, allocator: mem.Allocator) -> []Track_ID {
	output := make([dynamic]Track_ID, allocator)
	reserve(&output, 256)

	main_track, ok := l.tracks[main_track_id]
	if !ok do return nil

	for track_id, track in l.tracks {
		if track_id == main_track_id do continue

		if main_track.album != 0 && main_track.album == track.album {
			append(&output, track_id)
		}
		else if main_track.artist != 0 && main_track.artist == track.artist {
			append(&output, track_id)
		}
		else if main_track.genre != 0 && main_track.genre == track.genre {
			append(&output, track_id)
		}
	}

	return output[:]
}
