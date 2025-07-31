package server

import "base:runtime"
import "core:hash/xxhash"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import "core:sort"
import "core:os/os2"
import "core:fmt"
//import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:time"
import "core:math/rand"
import "core:unicode"

import "src:bindings/taglib"
import "src:path_pool"
import "src:util"

LIBRARY_MAX_TRACKS :: (32<<10)

Track_ID :: distinct u32
Playlist_ID :: struct {serial, pool: u32}

Metadata_Component :: enum {
	Album,
	Genre,
	Artist,
	Title,
	TrackNumber,
	Duration,
	Bitrate,
	Year,
	// Unix timestamp
	DateAdded,
	FileDate,
}

METADATA_COMPONENT_NAMES := [Metadata_Component]cstring {
	.Album = "Album",
	.Genre = "Genre",
	.Artist = "Artist",
	.Title = "Title",
	.Bitrate = "Bitrate",
	.Duration = "Duration",
	.TrackNumber = "Track",
	.Year = "Year",
	.DateAdded = "Date Added",
	.FileDate = "File Date",
}

Metadata_Value :: union {
	string,
	i64,
}

Track_Metadata :: struct {
	values: [Metadata_Component]Metadata_Value,
}

Track_Set :: struct {
	string_arena: mem.Dynamic_Arena,
	string_allocator: runtime.Allocator,
	path_allocator: path_pool.Pool,
	paths: [dynamic]path_pool.Path,
	metadata: [dynamic]Track_Metadata,
}

Track_Sort_Spec :: struct {
	metric: Metadata_Component,
	order: Sort_Order,
}

Library :: struct {
	// Incremented every time the library is altered
	serial: uint,
	allocator: runtime.Allocator,
	string_arena: mem.Dynamic_Arena,
	string_allocator: runtime.Allocator,
	path_allocator: path_pool.Pool,
	last_track_id: Track_ID,
	track_ids: [dynamic]Track_ID,
	track_path_hashes: [dynamic]u64,
	track_paths: [dynamic]path_pool.Path,
	track_metadata: [dynamic]Track_Metadata,
	next_playlist_id: u32,
	user_playlists: Playlist_List,
	user_playlist_dir: string,
	categories: struct {
		serial: uint,
		artists: Playlist_List,
		albums: Playlist_List,
		genres: Playlist_List,
		folders: Playlist_List,
	},
	folder_tree: Library_Folder_Tree,
	folder_tree_serial: uint,
}

Library_Track_Metadata_Alteration :: struct {
	values: [Metadata_Component]Maybe(Metadata_Value),
	tracks: []Track_ID,
}

library_init :: proc(lib: ^Library, user_playlist_dir: string) -> (ok: bool) {
	mem.dynamic_arena_init(&lib.string_arena)
	lib.string_allocator = mem.dynamic_arena_allocator(&lib.string_arena)
	lib.user_playlist_dir = user_playlist_dir
	lib.serial = 1
	if !os2.exists(lib.user_playlist_dir) {
		os2.make_directory(lib.user_playlist_dir)
	}
	ok = true
	return
}

library_destroy :: proc(lib: ^Library) {
	delete(lib.track_ids)
	delete(lib.track_metadata)
	delete(lib.track_paths)
	delete(lib.track_path_hashes)
	path_pool.destroy(lib.path_allocator)
	mem.dynamic_arena_destroy(&lib.string_arena)
	playlist_list_destroy(&lib.user_playlists)
	playlist_list_destroy(&lib.categories.artists)
	playlist_list_destroy(&lib.categories.albums)
	playlist_list_destroy(&lib.categories.genres)
	playlist_list_destroy(&lib.categories.folders)
}

library_hash_path :: proc(str: string) -> u64 {
	return xxhash.XXH3_64_default(transmute([]u8)str)
}

library_hash_string :: proc(str: string) -> u32 {
	return xxhash.XXH32(transmute([]u8)str)
}

get_default_metadata :: proc(path: string, string_allocator: runtime.Allocator) -> (metadata: Track_Metadata) {
	name := filepath.stem(filepath.base(path))
	track_set_string(&metadata, .Title, name, string_allocator)
	metadata.values[.DateAdded] = time.to_unix_seconds(time.now())
	return
}

get_file_metadata :: proc(path: string, string_allocator: runtime.Allocator) -> (metadata: Track_Metadata) {
	when ODIN_OS == .Windows {
		file := taglib.file_new_wchar(raw_data(util.win32_utf8_to_utf16(path, context.temp_allocator)))
	}
	else {
		file := taglib.file_new(strings.clone_to_cstring(path, context.temp_allocator))
	}

	metadata.values[.DateAdded] = time.to_unix_seconds(time.now())

	if fi, error := os2.stat(path, context.allocator); error == nil {
		metadata.values[.FileDate] = time.to_unix_seconds(fi.creation_time)
		defer os2.file_info_delete(fi, context.allocator)
	}

	if file == nil {return get_default_metadata(path, string_allocator)}
	defer taglib.file_free(file)

	tag := taglib.file_tag(file)
	if tag == nil {return get_default_metadata(path, string_allocator)}
	// @Volatile: This could mess up when trying to read file metadata from multiple
	// threads
	defer taglib.tag_free_strings()

	properties := taglib.file_audioproperties(file)

	track_set_cstring(&metadata, .Title, taglib.tag_title(tag), string_allocator)
	track_set_cstring(&metadata, .Artist, taglib.tag_artist(tag), string_allocator)
	track_set_cstring(&metadata, .Album, taglib.tag_album(tag), string_allocator)
	track_set_cstring(&metadata, .Genre, taglib.tag_genre(tag), string_allocator)
	metadata.values[.TrackNumber] = cast(i64) taglib.tag_track(tag)
	metadata.values[.Year] = cast(i64) taglib.tag_year(tag)
	if properties != nil {
		metadata.values[.Duration] = cast(i64) taglib.audioproperties_length(properties)
		metadata.values[.Bitrate] = cast(i64) taglib.audioproperties_bitrate(properties)
	}

	if (metadata.values[.Title].(string) or_else "") == "" {
		track_set_string(&metadata, .Title, filepath.stem(filepath.base(path)), string_allocator)
	}

	return
}

library_add_track :: proc(library: ^Library, path: string, metadata: Track_Metadata) -> Track_ID {
	path_loc := path_pool.store(&library.path_allocator, path)

	// If the track is already in the library, update the metadata
	if existing_index, exists := slice.linear_search(library.track_paths[:], path_loc); exists {
		orig_date_added := library.track_metadata[existing_index].values[.DateAdded]
		library.track_metadata[existing_index] = metadata
		library.track_metadata[existing_index].values[.DateAdded] = orig_date_added
		library.serial += 1
		return library.track_ids[existing_index]
	}
	
	library.last_track_id += 1
	id := library.last_track_id

	append(&library.track_ids, id)
	append(&library.track_path_hashes, library_hash_path(path))
	append(&library.track_paths, path_loc)
	append(&library.track_metadata, metadata)

	library.serial += 1

	return id
}

library_add_track_set :: proc(library: ^Library, set: Track_Set) {
	for index in 0..<len(set.metadata) {
		path_buf: [512]u8
		path := path_pool.retrieve(set.path_allocator, set.paths[index], path_buf[:])
		library_add_track(library, path, clone_track_metadata(set.metadata[index], library.string_allocator))
	}
}

library_lookup_track :: proc(library: Library, id: Track_ID) -> (int, bool) {
	return slice.linear_search(library.track_ids[:], id)
}

library_track_id_from_path_hash :: proc(library: Library, hash: u64) -> (id: Track_ID, found: bool) {
	index := slice.linear_search(library.track_path_hashes[:], hash) or_return
	return library.track_ids[index], true
}

library_get_track_path :: proc(library: Library, buf: []u8, track_id: Track_ID) -> (path: string, found: bool) {
	index := library_lookup_track(library, track_id) or_return
	return path_pool.retrieve(library.path_allocator, library.track_paths[index], buf), true
}

library_get_track_metadata :: proc(library: Library, track_id: Track_ID) -> (track: Track_Metadata, found: bool) {
	index := library_lookup_track(library, track_id) or_return
	return library.track_metadata[index], true
}

library_get_track_array_metadata :: proc(lib: Library, tracks: []Track_ID, allocator: mem.Allocator) -> []Track_Metadata {
	output := make([dynamic]Track_Metadata, allocator)
	reserve(&output, len(tracks))

	for track in tracks {
		index := library_lookup_track(lib, track) or_continue
		append(&output, lib.track_metadata[index])
	}

	return output[:]
}

library_dump_track :: proc(track_arg: Track_Metadata) {
	track := track_arg

	for component in Metadata_Component {
		fmt.println(METADATA_COMPONENT_NAMES[component], track.values[component])
	}
}

library_get_missing_tracks :: proc(lib: Library, output: ^[dynamic]Track_ID) {
	for i in 0..<len(lib.track_ids) {
		path_buf: [512]u8
		path := path_pool.retrieve(lib.path_allocator, lib.track_paths[i], path_buf[:])
		if !os2.exists(path) {
			append(output, lib.track_ids[i])
		}
	}
}

library_remove_missing_tracks :: proc(lib: ^Library) {
	to_remove: [dynamic]Track_ID
	defer delete(to_remove)

	library_get_missing_tracks(lib^, &to_remove)

	for track in to_remove {
		index := library_lookup_track(lib^, track) or_continue
		ordered_remove(&lib.track_ids, index)
		ordered_remove(&lib.track_metadata, index)
		ordered_remove(&lib.track_paths, index)
	}
	
	lib.serial += 1
}

library_update_categories :: proc(lib: ^Library) {
	if lib.categories.serial != lib.serial {
		log.debug("Rebuilding categories...")

		duration: time.Duration
		defer {
			log.debug(time.duration_milliseconds(duration), "ms")
			log.debug(len(lib.categories.albums.lists), "albums")
			log.debug(len(lib.categories.artists.lists), "artists")
			log.debug(len(lib.categories.genres.lists), "genres")
		}

		time.SCOPED_TICK_DURATION(&duration)


		lib.categories.serial = lib.serial
		playlist_list_join_metadata(&lib.categories.albums, lib^, .Album)
		playlist_list_join_metadata(&lib.categories.artists, lib^, .Artist)
		playlist_list_join_metadata(&lib.categories.genres, lib^, .Genre)
		playlist_list_join_folders(&lib.categories.folders, lib^)
	}
}

library_alloc_playlist_id :: proc(lib: ^Library) -> Playlist_ID {
	lib.next_playlist_id += 1
	return Playlist_ID{serial = lib.next_playlist_id}
}

library_create_playlist :: proc(lib: ^Library, name: string) -> (id: Playlist_ID, error: Error) {
	id = library_alloc_playlist_id(lib)
	playlist := playlist_list_add_new(&lib.user_playlists, name, id) or_return

	for {
		buf: [512]u8
		num := rand.uint32()
		path := fmt.bprint(buf[:], lib.user_playlist_dir, filepath.SEPARATOR_STRING, num, DEFAULT_PLAYLIST_FORMAT_EXTENSION, sep="")
		if !os2.exists(path) {
			fd, file_error := os2.create(path)
			if file_error != nil {return {}, Error.FileError}
			os2.close(fd)
			log.debug("New playlist", path)
			playlist.src_path = strings.clone(path)
			break
		}
	}

	return
}

library_get_playlist :: proc(lib: Library, id: Playlist_ID) -> ^Playlist {
	index, found := slice.linear_search(lib.user_playlists.list_ids[:], id)
	if found {return &lib.user_playlists.lists[index]}
	return nil
}

library_remove_playlist :: proc(lib: ^Library, id: Playlist_ID) {
	playlist_list_remove(&lib.user_playlists, id)
}

library_save_dirty_playlists :: proc(lib: Library) {
	for &playlist in lib.user_playlists.lists {
		if playlist.dirty {
			playlist.dirty = false
			playlist_file_save(lib, playlist, playlist.src_path)
		}
	}
}

library_add_playlist_from_file :: proc(lib: ^Library, path: string) -> bool {
	playlist: Playlist
	id := library_alloc_playlist_id(lib)
	playlist_init(&playlist, "", id)
	if !playlist_file_load(lib^, path, &playlist) {
		playlist_destroy(&playlist)
		return false
	}

	playlist.src_path = strings.clone(path)

	playlist_list_add(&lib.user_playlists, playlist)

	log.debug("Add playlist from file:", playlist.src_path)
	return true
}

library_scan_playlists :: proc(lib: ^Library) {
	files, error := os2.read_all_directory_by_path(lib.user_playlist_dir, context.allocator)
	if error != nil {return}
	defer os2.file_info_slice_delete(files, context.allocator)

	for file in files {
		library_add_playlist_from_file(lib, file.fullpath)
	}
}


library_alter_metadata :: proc(lib: ^Library, alter: Library_Track_Metadata_Alteration) {
	alter_track :: proc(lib: ^Library, md: ^Track_Metadata, component: Metadata_Component, value: Metadata_Value) {
		switch v in value {
			case string:
				track_set_string(md, component, v, lib.string_allocator)
			case i64:
				md.values[component] = v
		}
	}

	for component in Metadata_Component {
		if alter.values[component] == nil {continue}
		for track in alter.tracks {
			index := library_lookup_track(lib^, track) or_continue
			md := &lib.track_metadata[index]
			alter_track(lib, md, component, alter.values[component].?)
		}
	}

	lib.serial += 1
}

is_audio_file_supported :: proc(path: string) -> bool {
	ext := filepath.ext(path)
	return ext == ".mp3" ||
		ext == ".wav" ||
		ext == ".flac" ||
		ext == ".aiff" ||
		ext == ".alac" ||
		ext == ".aac" ||
		ext == ".ape" ||
		ext == ".opus" ||
		ext == ".m4a"
}

scan_directory_tracks :: proc(dir_path: string, set: ^Track_Set) {
	dir, dir_error := os2.open(dir_path)
	if dir_error != nil {return}
	defer os2.close(dir)

	iter := os2.read_directory_iterator_create(dir)
	defer os2.read_directory_iterator_destroy(&iter)

	if set.string_allocator.data == nil {
		mem.dynamic_arena_init(&set.string_arena)
		set.string_allocator = mem.dynamic_arena_allocator(&set.string_arena)
	}

	for {
		file, _ := os2.read_directory_iterator(&iter) or_break
		if file.type == .Directory {
			scan_directory_tracks(file.fullpath, set)
		}
		else if file.type == .Regular {
			if !is_audio_file_supported(file.fullpath) {continue}
			metadata := get_file_metadata(file.fullpath, set.string_allocator)
			append(&set.paths, path_pool.store(&set.path_allocator, file.fullpath))
			append(&set.metadata, metadata)
		}
	}

	return
}

// WARNING: Use sparingly! Leaks previous memory used for string!
track_set_string :: proc(track: ^Track_Metadata, dst: Metadata_Component, str: string, string_allocator: runtime.Allocator) {
	track.values[dst] = string(strings.clone_to_cstring(str, string_allocator))
}

// WARNING: Use sparingly! Leaks previous memory used for string!
track_set_cstring :: proc(track: ^Track_Metadata, dst: Metadata_Component, str: cstring, string_allocator: runtime.Allocator) {
	track.values[dst] = string(strings.clone_to_cstring(string(str), string_allocator))
}

library_compare_tracks :: proc(lib: Library, metric: Metadata_Component, a_index, b_index: int) -> bool {
	A := lib.track_metadata[a_index]
	B := lib.track_metadata[b_index]

	switch v in A.values[metric] {
		case i64: {
			return (A.values[metric].(i64) or_else 0) < (B.values[metric].(i64) or_else 0)
		}
		case string: {
			return strings.compare(A.values[metric].(string) or_else "", B.values[metric].(string) or_else "") > 0
		}
	}

	return false
}

library_sort_tracks :: proc(lib: Library, tracks: []Track_ID, spec: Track_Sort_Spec) {
	Collection :: struct {
		lib: Library,
		tracks: []Track_ID,
		metric: Metadata_Component,
	}

	collection: Collection
	iface: sort.Interface

	compare_proc :: proc(iface: sort.Interface, a, b: int) -> bool {
		collection := cast(^Collection)iface.collection
		metric := collection.metric
		a_index := library_lookup_track(collection.lib, collection.tracks[a]) or_return
		b_index := library_lookup_track(collection.lib, collection.tracks[b]) or_return
		return library_compare_tracks(collection.lib, metric, a_index, b_index)
	}

	len_proc :: proc(iface: sort.Interface) -> int {
		collection := cast(^Collection)iface.collection
		return len(collection.tracks)
	}

	swap_proc :: proc(iface: sort.Interface, a, b: int) {
		collection := cast(^Collection)iface.collection
		temp := collection.tracks[a]
		collection.tracks[a] = collection.tracks[b]
		collection.tracks[b] = temp
	}

	collection.lib = lib
	collection.tracks = tracks
	collection.metric = spec.metric
	iface.collection = &collection
	iface.len = len_proc
	iface.swap = swap_proc
	iface.less = compare_proc

	if spec.order == .Ascending {
		sort.sort(iface)
	}
	else {
		sort.reverse_sort(iface)
	}
}

library_sort :: proc(lib: ^Library, spec: Track_Sort_Spec) {
	Collection :: struct {
		lib: ^Library,
		metric: Metadata_Component,
	}

	swap :: proc(a, b: ^$T) {
		temp := a^
		a^ = b^
		b^ = temp
	}

	compare_proc :: proc(iface: sort.Interface, a, b: int) -> bool {
		collection := cast(^Collection)iface.collection
		metric := collection.metric
		return library_compare_tracks(collection.lib^, metric, a, b)
	}

	len_proc :: proc(iface: sort.Interface) -> int {
		collection := cast(^Collection)iface.collection
		lib := collection.lib
		return len(lib.track_ids)
	}

	swap_proc :: proc(iface: sort.Interface, a, b: int) {
		collection := cast(^Collection)iface.collection
		lib := collection.lib
		swap(&lib.track_ids[a], &lib.track_ids[b])
		swap(&lib.track_metadata[a], &lib.track_metadata[b])
		swap(&lib.track_paths[a], &lib.track_paths[b])
	}

	collection: Collection
	iface: sort.Interface
	collection.lib = lib
	collection.metric = spec.metric
	iface.collection = &collection
	iface.len = len_proc
	iface.swap = swap_proc
	iface.less = compare_proc

	if spec.order == .Ascending {
		sort.sort(iface)
	}
	else {
		sort.reverse_sort(iface)
	}

	lib.serial += 1
}

delete_track_set :: proc(set: ^Track_Set) {
	delete(set.metadata)
	delete(set.paths)
	path_pool.destroy(set.path_allocator)
	mem.dynamic_arena_destroy(&set.string_arena)
}

clone_track_metadata :: proc(src: Track_Metadata, string_allocator: runtime.Allocator) -> (dst: Track_Metadata) {
	for component in Metadata_Component {
		switch v in src.values[component] {
			case string: {
				dst.values[component] = string(strings.clone_to_cstring(v, string_allocator))
			}
			case i64: {
				dst.values[component] = v
			}
		}
	}

	return
}

Track_Filter_Spec :: struct {
	filter: string,
	components: bit_set[Metadata_Component],
}

@private
_filter_track_string :: proc(utf8_str: string, filter: []rune) -> bool {
	if len(utf8_str) == 0 {return false}
	if len(filter) == 0 {return true}

	str_rune_buf: [256]rune
	str := util.decode_utf8_to_runes(str_rune_buf[:], utf8_str)
	filter_len := len(filter)

	for &s in str {
		s = unicode.to_lower(s)
	}

	for &s in filter {
		s = unicode.to_lower(s)
	}
	
	for s in 0..<len(str) {
		fail := false

		for f in 0..<len(filter) {
			if s+f >= len(str) || str[s+f] != filter[f] {
				fail = true
				break
			}
		}

		if !fail {return true}
	}

	return false
}

filter_track_from_runes :: proc(lib: Library, spec: Track_Filter_Spec, track_id: Track_ID, filter: []rune) -> bool {
	md := library_get_track_metadata(lib, track_id) or_return
	for component in Metadata_Component {
		if component in spec.components {
			val := md.values[component].(string) or_continue
			if _filter_track_string(val, filter) {
				return true
			}
		}
	}

	return false
}

filter_tracks :: proc(lib: Library, spec: Track_Filter_Spec, input: []Track_ID, output: ^[dynamic]Track_ID) {
	filter_rune_buf: [512]rune
	filter_runes := util.decode_utf8_to_runes(filter_rune_buf[:], spec.filter)

	for track in input {
		if filter_track_from_runes(lib, spec, track, filter_runes) {
			append(output, track)
		}
	}
}
