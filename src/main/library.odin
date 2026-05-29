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


Track_Group_ID :: distinct i16
Track_Group_ID_Set :: [6]Track_Group_ID

// 0 means none
// Index into array
Artist_ID :: Track_Group_ID
Genre_ID :: Track_Group_ID
Album_ID :: Track_Group_ID
Dir_ID :: distinct i16

Track_Flag :: enum {
	Missing,
	Overwrite, // Use on Track_Data struct to tell library to overwrite an existing track
}

Track_Protocol :: enum u8 {
	File,
}

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
	track_no:         i16,
	channels:         i16,
	samplerate:       i32,
	release_year:     i32,
	bitrate_kbps:     i32,

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
	artists:          Track_Group_ID_Set,
	genres:           Track_Group_ID_Set,
	album:            Track_Group_ID,
	track_no:         i16,
	channels:         i16,
	bitrate_kbps:     i16,
	format:           Audio_File_Format,
	flags:            bit_set[Track_Flag; u8],
	protocol:         Track_Protocol,
}

Track_Group :: struct {
	name:            string,
	lower_case_name: string,
	name_hash:       u32,
	sort_index:      int,
	serial:          uint,
	uid:             UID,
	totals:          Track_List_Totals,
}

Track_Group_Type :: enum {Artist, Genre, Album}

// Entries never get removed or rearranged for the duration of the program
// so it is safe to store an index into the entries array
Track_Group_List :: struct {
	allocator:      mem.Allocator,
	type:           Track_Group_Type,
	entries:        [dynamic]Track_Group,
	sorted_indices: [dynamic]int,
	serial:         uint,
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

	track_common_strings: [Track_Group_Type]Track_Group_List,

	playlists: hm.Static_Handle_Map(256, Playlist, Playlist_Handle),
	playlists_serial: uint,
	
	folder_cover_art: map[u64]string,
	
	// Serial of library when groups were sorted
	group_sort_serial:           uint,
	common_string_totals_serial: uint,
	serial:                      uint,
}

library_init :: proc(l: ^Library) {
	log.debug("size_of(Track) =", size_of(Track))

	l.allocators.track_data = allocator_map_add_dynamic_arena(&l.allocator_map, "track_data")
	l.allocators.track_map = allocator_map_add_heap(&l.allocator_map, "track_map")
	l.allocators.temp = allocator_map_add_dynamic_arena(&l.allocator_map, "temp")
	l.serial = 1

	l.tracks = make_map_cap(map[Track_ID]Track, 4096, l.allocators.track_map)
	l.url_hash_map = make_map_cap(map[u64]Track_ID, 4096, l.allocators.track_map)

	for &t, type in l.track_common_strings {
		track_group_list_init(&t, type, l.allocators.track_data)
	}
}

library_destroy :: proc(l: ^Library) {
	delete(l.tracks)
	delete(l.folder_cover_art)
	delete(l.url_hash_map)
}

library_update :: proc(l: ^Library) {
	if l.group_sort_serial != l.serial {
		log.debug("Sorting track groups...")
		l.group_sort_serial = l.serial
	}

	// --------------------------------------------------------------------------
	// Recalculate common string totals
	// --------------------------------------------------------------------------
	if l.common_string_totals_serial != l.serial {
		TIME_SCOPE("Calculate common string totals")

		l.common_string_totals_serial = l.serial

		for type in Track_Group_Type {
			list := &l.track_common_strings[type]
			for &e in list.entries {
				e.totals = {}
			}
		}

		for _, track in l.tracks {
			for i in 0..<len(track.artists) {
				if i != 0 && track.artists[i] == 0 do continue
				tots := &l.track_common_strings[.Artist].entries[track.artists[i]].totals

				tots.track_count += 1
				tots.file_size   += auto_cast track.file_size
				tots.duration    += auto_cast track.duration_seconds
			}

			for i in 0..<len(track.genres) {
				if i != 0 && track.genres[i] == 0 do continue
				tots := &l.track_common_strings[.Genre].entries[track.genres[i]].totals

				tots.track_count += 1
				tots.file_size   += auto_cast track.file_size
				tots.duration    += auto_cast track.duration_seconds
			}

			tots := &l.track_common_strings[.Album].entries[track.album].totals
			tots.duration    += auto_cast track.duration_seconds
			tots.file_size   += track.file_size
			tots.track_count += 1
		}
	}
}

library_add_track :: proc(
	l: ^Library, data: Track_Data,
	update_existing := false,
) -> (id: Track_ID, error: Error) {
	hash := hash_track_url(data.url)
	if hash == 0 do return {}, false

	update_existing := update_existing
	update_existing |= .Overwrite in data.flags

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


read_audio_file_metadata :: proc(path: string, allocator: mem.Allocator) -> (track: Track_Data, found: bool) {
	track.format = audio_file_format_from_extension(filepath.ext(path)) or_return

	TIME_SCOPE("TagLib probe")

	file := taglib_open(path)
	
	if file == nil {
		log.warn("Failed to open file", path)
		return
	}
	defer taglib.file_free(file)

	found = true
	track.url = strings.clone(path, allocator)
	track.protocol = .File

	if file_info, error := os.stat(path, context.allocator); error == nil {
		track.file_date = file_info.creation_time
		track.file_size = auto_cast file_info.size
		os.file_info_delete(file_info, context.allocator)
	}
	
	tag := taglib.file_tag(file)
	if tag != nil {
		defer taglib.tag_free_strings()

		title := taglib.tag_title(tag)
		artist := taglib.tag_artist(tag)
		album := taglib.tag_album(tag)
		genre := taglib.tag_genre(tag)
		year := taglib.tag_year(tag)
		track_no := taglib.tag_track(tag)

		if title != nil do track.title = strings.clone(string(title), allocator)
		if album != nil do track.album = strings.clone(string(album), allocator)
		if genre != nil do track.genre = strings.clone(string(genre), allocator)
		if artist != nil do track.artist = strings.clone(string(artist), allocator)
		track.release_year = auto_cast year
		track.track_no = auto_cast track_no
	}

	if track.title == "" {
		track.title = strings.clone(filepath.short_stem(filepath.base(path)), allocator)
	}

	audio_props := taglib.file_audioproperties(file)
	if audio_props != nil {
		track.bitrate_kbps = auto_cast taglib.audioproperties_bitrate(audio_props)
		track.duration_seconds = auto_cast taglib.audioproperties_length(audio_props)
		track.samplerate = auto_cast taglib.audioproperties_samplerate(audio_props)
		track.channels = auto_cast taglib.audioproperties_channels(audio_props)
	}

	return
}

// Adds or overwrites track with given ID
library_add_or_update_track :: proc(
	l: ^Library, id: Track_ID, data: Track_Data,
) -> Error {
	hash := hash_track_url(data.url)
	if hash == 0 do return .InvalidInput
	if id not_in l.tracks do l.tracks[id] = {}

	track := &l.tracks[id]

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
	track.flags            = data.flags ~ {.Overwrite}
	track.protocol         = data.protocol
	track.album            = library_get_or_add_album(l, data.album, id)
	track.date_added       = time.now()

	artists := strings.split(data.artist, ",")
	defer delete(artists)

	for artist, i in artists {
		if i >= len(track.artists) do break
		track.artists[i] = library_get_or_add_artist(l, strings.trim(artist, " "), track.id)
	}

	genres := strings.split(data.genre, ", ")
	defer delete(genres)

	for genre, i in genres {
		if i >= len(track.genres) do break
		track.genres[i] = library_get_or_add_genre(l, strings.trim(genre, " "), track.id)
	}
	
	l.url_hash_map[hash] = id
	l.serial += 1

	return nil
}

library_remove_tracks :: proc(l: ^Library, tracks: []Track_ID) {
	for track_id in tracks {
		track := l.tracks[track_id] or_continue
		url_hash := hash_track_url(track.url)

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

library_get_artist_name :: proc(l: Library, id: Artist_ID) -> string {
	return l.track_common_strings[.Artist].entries[id].name
}

library_get_album_name :: proc(l: Library, id: Album_ID) -> string {
	return l.track_common_strings[.Album].entries[id].name
}

library_get_genre_name :: proc(l: Library, id: Genre_ID) -> string {
	return l.track_common_strings[.Genre].entries[id].name
}	

library_get_artist_name_lower :: proc(l: Library, id: Artist_ID) -> string {
	return l.track_common_strings[.Artist].entries[id].lower_case_name
}

library_get_album_name_lower :: proc(l: Library, id: Album_ID) -> string {
	return l.track_common_strings[.Album].entries[id].lower_case_name
}

library_get_genre_name_lower :: proc(l: Library, id: Genre_ID) -> string {
	return l.track_common_strings[.Genre].entries[id].lower_case_name
}

library_save :: proc(l: Library, path: string) -> Error {
	TIME_SCOPE("Save library", path)
	return track_db_save(l, path)
}

library_load :: proc(l: ^Library, path: string) -> Error {
	TIME_SCOPE("Load library", path)

	track_db_load(l, path) or_return

	track_group_list_sort(&l.track_common_strings[.Artist])
	track_group_list_sort(&l.track_common_strings[.Genre])
	track_group_list_sort(&l.track_common_strings[.Album])

	return nil
}

library_get_track :: proc(l: Library, id: Track_ID) -> (track: Track, found: bool) {
	return l.tracks[id]
}

library_get_tracks_in_group :: proc(
	l:          Library,
	group_type: Track_Group_Type,
	group_id:   Track_Group_ID,
	output:    ^[dynamic]Track_ID,
) {
	switch group_type {
	case .Artist:
		for id, track in l.tracks {
			for a, i in track.artists {
				if i != 0 && a == 0 do break
				if a == group_id {
					append(output, id)
					break
				}
			}
		}
	case .Genre:
		for id, track in l.tracks {
			for a, i in track.genres {
				if i != 0 && a == 0 do break
				if a == group_id {
					append(output, id)
					break
				}
			}
		}
	case .Album:
		for id, track in l.tracks {
			if track.album == group_id {
				append(output, id)
			}
		}
	}
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
track_group_list_find_entry :: proc(tg: ^Track_Group_List, hash: u32) -> (index: int, found: bool) {
	count := len(tg.entries)
	for ent, i in tg.entries {
		if ent.name_hash == hash do return i, true
	}
	return
}

track_group_list_init :: proc(list: ^Track_Group_List, type: Track_Group_Type, allocator: mem.Allocator) {
	list.type = type
	list.allocator = allocator
	reserve(&list.entries, 512)
	append(&list.entries, Track_Group {
		name = "",
		name_hash = stable_hash_string_32(""),
	})
}

track_group_list_get_or_add_entry :: proc(
	list: ^Track_Group_List, str: string
) -> int {
	hash := stable_hash_string_32(str)
	index := track_group_list_find_entry(list, hash) or_else -1

	if index == -1 {
		index = len(list.entries)
		append(&list.entries, Track_Group {
			name = strings.clone(str, list.allocator),
			lower_case_name = strings.to_lower(str, list.allocator),
			name_hash = stable_hash_string_32(str),
			uid = generate_uid(),
		})
	}

	entry := &list.entries[index]
	entry.serial += 1
	list.serial += 1

	return index
}

// Broken, but keep for future
track_group_list_sort :: proc(list: ^Track_Group_List) {
	resize(&list.sorted_indices, len(list.entries))

	for _, i in list.entries {
		list.sorted_indices[i] = i
	}

	iface := sort.Interface {
		collection = list,
		len = proc(it: sort.Interface) -> int {
			tg := cast(^Track_Group_List) it.collection
			return len(tg.entries)
		},
		swap = proc(it: sort.Interface, a, b: int) {
			tg := cast(^Track_Group_List) it.collection
			tg.sorted_indices[a], tg.sorted_indices[b] = tg.sorted_indices[b], tg.sorted_indices[a]
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			tg := cast(^Track_Group_List) it.collection
			A := tg.sorted_indices[a]
			B := tg.sorted_indices[b]
			return strings.compare(tg.entries[A].name, tg.entries[B].name) < 0
		}
	}

	sort.sort(iface)
}

library_get_or_add_artist :: proc(l: ^Library, name: string, track_id: Track_ID) -> Artist_ID {
	return auto_cast track_group_list_get_or_add_entry(&l.track_common_strings[.Artist], name)
}

library_get_or_add_album :: proc(l: ^Library, name: string, track_id: Track_ID) -> Album_ID {
	return auto_cast track_group_list_get_or_add_entry(&l.track_common_strings[.Album], name)
}

library_get_or_add_genre :: proc(l: ^Library, name: string, track_id: Track_ID) -> Genre_ID {
	return auto_cast track_group_list_get_or_add_entry(&l.track_common_strings[.Genre], name)
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

scan_directory_for_cover_art :: proc(
	dir: string, allocator: mem.Allocator, temp_allocator: mem.Allocator
) -> (path: string, error: Error) {
	files := os.read_all_directory_by_path(dir, temp_allocator) or_return
	defer os.file_info_slice_delete(files, temp_allocator)

	for file in files {
		if file_is_type(file.fullpath, .Image) {
			path = strings.clone(file.fullpath, allocator) or_return
			return
		}
	}

	return
}

library_scan_directory_for_cover_art :: proc(l: ^Library, dir: string) -> (error: Error) {
	hash := stable_hash_string_64(dir)
	if hash in l.folder_cover_art do return
	log.debug("Scanning directory", dir, "for cover art")

	path := scan_directory_for_cover_art(dir, l.allocators.track_data, l.allocators.temp) or_else ""
	l.folder_cover_art[hash] = path

	return
}

Track_List_Totals :: struct {
	duration:    i64,
	file_size:   i64,
	track_count: int,
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
		for artist in t.artists {
			if artist == 0 do break
			if strings.contains(library_get_artist_name_lower(l, artist), filter) do return true
		}
	}

	if .Album in metrics {
		if strings.contains(library_get_album_name_lower(l, t.album), filter) do return true
	}

	if .Genre in metrics {
		for genre in t.genres {
			if genre == 0 do break
			if strings.contains(library_get_genre_name_lower(l, genre), filter) do return true
		}
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

filter_track_groups :: proc(l: Library, output: ^#soa[dynamic]Track_Group, tg: Track_Group_List, filter: string) {
	lower_filter := strings.to_lower(filter, l.allocators.temp)
	defer delete(lower_filter)

	for entry in tg.entries {
		if strings.contains(entry.lower_case_name, lower_filter) {
			append(output, entry)
		}
	}
}

// -----------------------------------------------------------------------------
// Misc
// -----------------------------------------------------------------------------

library_join_track_group_names_to_builder :: proc(
	l:    Library,
	b:    ^strings.Builder,
	ids:  Track_Group_ID_Set,
	type: Track_Group_Type
) -> string {
	if ids[0] == 0 do return ""
	list := l.track_common_strings[type]

	strings.write_string(b, list.entries[ids[0]].name)

	for i in 1..<len(ids) {
		if ids[i] == 0 do break
		strings.write_string(b, ", ")
		strings.write_string(b, list.entries[ids[i]].name)
	}

	return strings.to_string(b^)
}

library_join_track_group_names_to_allocator :: proc(
	l:         Library,
	ids:       Track_Group_ID_Set,
	type:      Track_Group_Type,
	allocator: mem.Allocator
) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	return library_join_track_group_names_to_builder(l, &b, ids, type)
}

library_join_track_group_names :: proc {
	library_join_track_group_names_to_allocator,
	library_join_track_group_names_to_builder,
}

// -----------------------------------------------------------------------------
// Radio
// -----------------------------------------------------------------------------

library_build_radio :: proc(l: Library, main_track_id: Track_ID, allocator: mem.Allocator) -> []Track_ID {
	TIME_SCOPE("Build radio")
	
	output := make([dynamic]Track_ID, allocator)
	reserve(&output, 256)

	main_track, ok := l.tracks[main_track_id]
	if !ok do return nil

	track_loop: for track_id, &track in l.tracks {
		if track_id == main_track_id do continue

		if main_track.album != 0 && main_track.album == track.album {
			append(&output, track_id)
		}
		else if main_track.artists[0] != 0 {
			for a in main_track.artists {
				if track_has_artist(track, a) {
					append(&output, track_id)
					continue track_loop
				}
			}
		}
		else if main_track.genres[0] != 0 {
			for a in main_track.genres {
				if track_has_genre(track, a) {
					append(&output, track_id)
					continue track_loop
				}
			}
		}
	}

	return output[:]
}

// -----------------------------------------------------------------------------
// Track helpers
// -----------------------------------------------------------------------------

track_has_artist :: proc(track: Track, a: Artist_ID) -> bool {
	for artist in track.artists {
		if artist == 0 do return false
		if artist == a do return true
	}

	return false
}

track_has_genre :: proc(track: Track, g: Genre_ID) -> bool {
	for genre in track.genres {
		if genre == 0 do return false
		if genre == g do return true
	}

	return false
}
