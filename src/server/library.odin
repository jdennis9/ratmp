/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

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

Track_Property_ID :: enum {
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

TRACK_PROPERTY_NAMES := [Track_Property_ID]cstring {
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

Track_Property :: union {
	string,
	i64,
}

Track_Properties :: [Track_Property_ID]Track_Property

Track_Set :: struct {
	string_arena: mem.Dynamic_Arena,
	string_allocator: runtime.Allocator,
	path_allocator: path_pool.Pool,
	paths: [dynamic]path_pool.Path,
	metadata: [dynamic]Track_Properties,
	cover_art: map[u64]string,
}

Track_Sort_Spec :: struct {
	metric: Track_Property_ID,
	order: Sort_Order,
}

Track :: struct {
	id: Track_ID,
	path: path_pool.Path,
	path_hash: u64,
	properties: Track_Properties,
}

Library :: struct {
	// Incremented every time the library is altered
	serial: uint,
	allocator: runtime.Allocator,
	string_arena: mem.Dynamic_Arena,
	string_allocator: runtime.Allocator,
	path_allocator: path_pool.Pool,
	last_track_id: Track_ID,

	tracks: #soa[dynamic]Track,

	dir_cover_files: map[u64]string,
	next_playlist_id: u32,
	user_playlists: Playlist_List,
	user_playlist_dir: string,
	categories: struct {
		serial: uint,
		artists: Playlist_List,
		albums: Playlist_List,
		genres: Playlist_List,
	},
	folder_tree: Library_Folder_Tree,
	folder_tree_serial: uint,
}

Library_Track_Metadata_Alteration :: struct {
	values: [Track_Property_ID]Track_Property,
	tracks: []Track_ID,
	write_to_file: bool,
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
	delete(lib.tracks)
	path_pool.destroy(lib.path_allocator)
	mem.dynamic_arena_destroy(&lib.string_arena)
	playlist_list_destroy(&lib.user_playlists)
	playlist_list_destroy(&lib.categories.artists)
	playlist_list_destroy(&lib.categories.albums)
	playlist_list_destroy(&lib.categories.genres)
}

library_hash_path :: proc(str: string) -> u64 {
	return xxhash.XXH3_64_default(transmute([]u8)str)
}

library_hash_string :: proc(str: string) -> u32 {
	return xxhash.XXH32(transmute([]u8)str)
}

get_file_date :: proc(path: string) -> i64 {
	if fi, error := os2.stat(path, context.allocator); error == nil {
		defer os2.file_info_delete(fi, context.allocator)
		return time.to_unix_seconds(fi.creation_time)
	}
	return 0
}

library_find_track_by_path_hash :: proc(lib: Library, hash: u64) -> (int, bool) {
	for track, index in lib.tracks {
		if track.path_hash == hash {
			return index, true
		}
	}

	return 0, false
}

library_get_all_track_ids :: proc(lib: Library) -> []Track_ID {
	return lib.tracks.id[:len(lib.tracks)]
}

library_add_track :: proc(lib: ^Library, path: string, properties: Track_Properties) -> Track_ID {
	path_loc := path_pool.store(&lib.path_allocator, path)
	path_hash := library_hash_path(path)

	// If the track is already in the library, update the metadata
	if existing_index, exists := library_find_track_by_path_hash(lib^, path_hash); exists {
		track := &lib.tracks[existing_index]
		orig_date_added := track.properties[.DateAdded]
		track.properties = properties
		track.properties[.DateAdded] = orig_date_added
		lib.serial += 1
		return track.id
	}
	
	lib.last_track_id += 1
	id := lib.last_track_id

	track := Track {
		id = id,
		path = path_loc,
		path_hash = path_hash,
		properties = properties,
	}

	if track.properties[.DateAdded] == nil {
		track.properties[.DateAdded] = i64(time.to_unix_seconds(time.now()))
	}

	append(&lib.tracks, track)

	lib.serial += 1

	return id
}

library_add_track_set :: proc(library: ^Library, set: Track_Set) {
	for index in 0..<len(set.metadata) {
		path_buf: [512]u8
		path := path_pool.retrieve(set.path_allocator, set.paths[index], path_buf[:])
		library_add_track(library, path, track_properties_clone(set.metadata[index], library.string_allocator))
	}

	for hash, path in set.cover_art {
		log.debug("Add cover art from scan:", hash, "=>", path)
		library_add_folder_cover_art_from_hash(library, hash, path)
	}
}

library_find_track_index :: proc(lib: Library, id: Track_ID) -> (int, bool) {
	for track, index in lib.tracks {
		if track.id == id {
			return index, true
		}
	}

	return 0, false
}

library_find_track :: proc(lib: Library, id: Track_ID) -> (track: Track, found: bool) {
	index := library_find_track_index(lib, id) or_return
	return lib.tracks[index], true
}

library_get_track_path :: proc(lib: Library, buf: []u8, track_index: int) -> (path: string, found: bool) {
	return path_pool.retrieve(lib.path_allocator, lib.tracks[track_index].path, buf), true
}

library_get_track_path_cstring :: proc(lib: Library, buf: []u8, track_index: int) -> (path: cstring, found: bool) {
	return path_pool.retrieve_cstring(lib.path_allocator, lib.tracks[track_index].path, buf), true
}

library_find_track_path :: proc(lib: Library, buf: []u8, track_id: Track_ID) -> (path: string, found: bool) {
	index := library_find_track_index(lib, track_id) or_return
	return library_get_track_path(lib, buf, index)
}

library_find_track_path_cstring :: proc(lib: Library, buf: []u8, track_id: Track_ID) -> (path: cstring, found: bool) {
	index := library_find_track_index(lib, track_id) or_return
	return library_get_track_path_cstring(lib, buf, index)
}

library_get_missing_tracks :: proc(lib: Library, output: ^[dynamic]Track_ID) {
	for track in lib.tracks {
		path_buf: [512]u8
		path := path_pool.retrieve(lib.path_allocator, track.path, path_buf[:])
		if !os2.exists(path) {
			append(output, track.id)
		}
	}
}

library_remove_track :: proc(lib: ^Library, id: Track_ID) -> bool {
	index := library_find_track_index(lib^, id) or_return
	ordered_remove_soa(&lib.tracks, index)
	lib.serial += 1
	return true
}

library_remove_missing_tracks :: proc(lib: ^Library) {
	to_remove: [dynamic]Track_ID
	defer delete(to_remove)

	library_get_missing_tracks(lib^, &to_remove)

	for track in to_remove {
		library_remove_track(lib, track)
	}	
}

library_update_categories :: proc(lib: ^Library) {
	if lib.categories.serial != lib.serial {
		log.debug("Rebuilding categories...")

		when ODIN_DEBUG {
			duration: time.Duration
			defer {
				log.debug(time.duration_milliseconds(duration), "ms")
				log.debug(len(lib.categories.albums.lists), "albums")
				log.debug(len(lib.categories.artists.lists), "artists")
				log.debug(len(lib.categories.genres.lists), "genres")
			}

			time.SCOPED_TICK_DURATION(&duration)
		}

		lib.categories.serial = lib.serial
		playlist_list_join_metadata(&lib.categories.albums, lib^, .Album)
		playlist_list_join_metadata(&lib.categories.artists, lib^, .Artist)
		playlist_list_join_metadata(&lib.categories.genres, lib^, .Genre)
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

library_scan_folder_for_cover_art :: proc(lib: ^Library, dir: string) {
	dir_hash := library_hash_path(dir)

	if _, exists := lib.dir_cover_files[dir_hash]; exists {return}

	files, _ := os2.read_all_directory_by_path(dir, context.allocator)
	defer os2.file_info_slice_delete(files, context.allocator)

	log.debug("Searching directory", dir, "for cover art")

	for file in files {
		ext := filepath.ext(file.name)
		if is_image_ext_supported(ext) {
			log.debug("Found cover", file.name)
			lib.dir_cover_files[dir_hash] = strings.clone(file.fullpath, lib.string_allocator)
			return
		}
	}
}

library_find_track_folder_cover_art :: proc(lib: Library, track_index: int) -> (cover: string, found: bool) {
	path_buf: [512]u8
	path := path_pool.retrieve(lib.path_allocator, lib.tracks[track_index].path, path_buf[:])
	dir := filepath.dir(path)
	defer delete(dir)

	return library_find_folder_cover_art(lib, dir)
}

library_find_folder_cover_art :: proc(lib: Library, dir: string) -> (cover: string, found: bool) {
	cover, found = lib.dir_cover_files[library_hash_path(dir)]
	if found {found = cover != ""}
	return
}

library_add_folder_cover_art_from_path :: proc(lib: ^Library, dir: string, cover_path: string) {
	dir_hash := library_hash_path(dir)
	if _, exists := lib.dir_cover_files[dir_hash]; exists {return}
	lib.dir_cover_files[dir_hash] = strings.clone(cover_path, lib.string_allocator)
}

library_add_folder_cover_art_from_hash :: proc(lib: ^Library, hash: u64, cover_path: string) {
	if _, exists := lib.dir_cover_files[hash]; exists {return}
	lib.dir_cover_files[hash] = strings.clone(cover_path, lib.string_allocator)
}

library_add_folder_cover_art :: proc {
	library_add_folder_cover_art_from_path,
	library_add_folder_cover_art_from_hash,
}

library_save_track_metadata_to_file :: proc(lib: Library, track_index: int) -> bool {
	path_buf: [512]u8

	md_cstring :: proc(md: Track_Properties, component: Track_Property_ID) -> cstring {
		return strings.unsafe_string_to_cstring(md[component].(string) or_else string(cstring("")))
	}

	md := lib.tracks[track_index].properties
	path := path_pool.retrieve_cstring(lib.path_allocator, lib.tracks[track_index].path, path_buf[:])

	log.debug("Save metadata for", path)

	file := taglib.file_new(path)
	if file == nil {return false}
	defer taglib.file_free(file)

	tag := taglib.file_tag(file)
	if tag == nil {return false}
	defer taglib.tag_free_strings()

	taglib.tag_set_year(tag, auto_cast(md[.Year].(i64) or_else 0))
	taglib.tag_set_track(tag, auto_cast(md[.TrackNumber].(i64) or_else 0))
	taglib.tag_set_title(tag, md_cstring(md, .Title))
	taglib.tag_set_artist(tag, md_cstring(md, .Artist))
	taglib.tag_set_album(tag, md_cstring(md, .Album))
	taglib.tag_set_genre(tag, md_cstring(md, .Genre))

	taglib.file_save(file)

	return true
}

library_alter_metadata :: proc(lib: ^Library, alter: Library_Track_Metadata_Alteration) {
	alter_track :: proc(lib: ^Library, md: ^Track_Properties, component: Track_Property_ID, value: Track_Property) {
		switch v in value {
			case string: {
				track_set_string(md, component, v, lib.string_allocator)
			}
			case i64: {
				md[component] = v
			}
		}
	}

	for component in Track_Property_ID {
		if alter.values[component] == nil {continue}
		for track in alter.tracks {
			index := library_find_track_index(lib^, track) or_continue
			md := &lib.tracks[index].properties
			alter_track(lib, md, component, alter.values[component])

			if alter.write_to_file {
				library_save_track_metadata_to_file(lib^, index)
			}
		}
	}

	lib.serial += 1
}

is_image_ext_supported :: proc(ext: string) -> bool {
	return ext == ".jpg" ||
		ext == ".jpeg" ||
		ext == ".png"
}

is_image_file_supported :: proc(path: string) -> bool {
	return is_image_ext_supported(filepath.ext(path))
}

is_audio_ext_supported :: proc(ext: string) -> bool {
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

is_audio_file_supported :: proc(path: string) -> bool {
	return is_audio_ext_supported(filepath.ext(path))
}

scan_directory_tracks :: proc(dir_path: string, set: ^Track_Set) {
	dir_hash := library_hash_path(dir_path)
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
			if is_audio_file_supported(file.name) {
				metadata := track_properties_from_file(file.fullpath, set.string_allocator)
				append(&set.paths, path_pool.store(&set.path_allocator, file.fullpath))
				append(&set.metadata, metadata)
			}
			else if is_image_file_supported(file.name) {
				if _, exists := set.cover_art[dir_hash]; exists {continue}
				set.cover_art[dir_hash] = strings.clone(file.fullpath, set.string_allocator)
			}
		}
	}

	return
}

// WARNING: Use sparingly! Leaks previous memory used for string!
track_set_string :: proc(track: ^Track_Properties, dst: Track_Property_ID, str: string, string_allocator: runtime.Allocator) {
	track[dst] = string(strings.clone_to_cstring(str, string_allocator))
}

// WARNING: Use sparingly! Leaks previous memory used for string!
track_set_cstring :: proc(track: ^Track_Properties, dst: Track_Property_ID, str: cstring, string_allocator: runtime.Allocator) {
	track[dst] = string(strings.clone_to_cstring(string(str), string_allocator))
}

library_compare_tracks :: proc(lib: Library, metric: Track_Property_ID, a_index, b_index: int) -> bool {
	A := lib.tracks[a_index]
	B := lib.tracks[b_index]

	switch v in A.properties[metric] {
		case i64: {
			return (
				A.properties[metric].(i64) or_else 0) <
				(B.properties[metric].(i64) or_else 0
			)
		}
		case string: {
			return strings.compare(
				A.properties[metric].(string) or_else "",
				B.properties[metric].(string) or_else ""
			) > 0
		}
	}

	return false
}

library_sort_tracks :: proc(lib: Library, tracks: []Track_ID, spec: Track_Sort_Spec) {
	Collection :: struct {
		lib: Library,
		tracks: []Track_ID,
		metric: Track_Property_ID,
	}

	collection: Collection
	iface: sort.Interface

	compare_proc :: proc(iface: sort.Interface, a, b: int) -> bool {
		collection := cast(^Collection)iface.collection
		metric := collection.metric
		a_index := library_find_track_index(collection.lib, collection.tracks[a]) or_return
		b_index := library_find_track_index(collection.lib, collection.tracks[b]) or_return
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
		metric: Track_Property_ID,
	}

	compare_proc :: proc(iface: sort.Interface, a, b: int) -> bool {
		collection := cast(^Collection)iface.collection
		metric := collection.metric
		return library_compare_tracks(collection.lib^, metric, a, b)
	}

	len_proc :: proc(iface: sort.Interface) -> int {
		collection := cast(^Collection)iface.collection
		lib := collection.lib
		return len(lib.tracks)
	}

	swap_proc :: proc(iface: sort.Interface, a, b: int) {
		collection := cast(^Collection)iface.collection
		lib := collection.lib
		temp := lib.tracks[a]
		lib.tracks[a] = lib.tracks[b]
		lib.tracks[b] = temp
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

track_set_delete :: proc(set: ^Track_Set) {
	delete(set.metadata)
	delete(set.paths)
	delete(set.cover_art)
	path_pool.destroy(set.path_allocator)
	mem.dynamic_arena_destroy(&set.string_arena)
}

/*clone_track_metadata :: proc(src: Track_Metadata, string_allocator: runtime.Allocator) -> (dst: Track_Metadata) {
	for component in Track_Property_ID {
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
}*/

Track_Filter_Spec :: struct {
	filter: string,
	components: bit_set[Track_Property_ID],
}

@private
_filter_track_string :: proc(utf8_str: string, filter: []rune) -> bool {
	if len(utf8_str) == 0 {return false}
	if len(filter) == 0 {return true}

	str_rune_buf: [256]rune
	str := util.decode_utf8_to_runes(str_rune_buf[:], utf8_str)

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
	track := library_find_track(lib, track_id) or_return
	md := track.properties
	for component in Track_Property_ID {
		if component in spec.components {
			val := md[component].(string) or_continue
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
