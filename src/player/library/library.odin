/*
	RAT MP: A lightweight graphical music player
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
package library

import "core:os"
import "core:os/os2"
import "core:log"
import "core:path/filepath"
import "core:hash/xxhash"
import "core:strings"
import "core:unicode"
import "core:math/rand"
import "core:fmt"
import "core:strconv"
import "core:encoding/json"
import "core:time"
import "core:slice"
import stbi "vendor:stb/image"

import "bindings:taglib"
import "player:path_pool"
import "player:util"
import "player:video"
import "player:decoder"

Track_ID :: u32

Playlist_ID :: struct {
	user: u32, // ID of playlist created by user
	group: u32, // ID of group playlist belongs to
}

Add_Playlist_Error :: enum {
	None,
	EmptyName,
	NameExists,
	NameReserved,
}

@private
Pool_String :: struct {
	offset, length: int,
}

MAX_TRACK_TITLE_LENGTH :: 127
MAX_TRACK_ARTIST_LENGTH :: 63
MAX_TRACK_ALBUM_LENGTH :: 63
MAX_TRACK_GENRE_LENGTH :: 31

Raw_Track_Info :: struct {
	path: path_pool.Path,
	title: [MAX_TRACK_TITLE_LENGTH+1]u8,
	artist: [MAX_TRACK_ARTIST_LENGTH+1]u8,
	album: [MAX_TRACK_ALBUM_LENGTH+1]u8,
	genre: [MAX_TRACK_GENRE_LENGTH+1]u8,
	duration_seconds: int,
	track_number: int,
	year: int,
	bitrate: int,
	marked_for_removal: bool,
}

Track_Info :: struct {
	id: Track_ID,
	title: cstring,
	artist: cstring,
	album: cstring,
	genre: cstring,
	duration_seconds: int,
	track_number: int,
	year: int,
	bitrate: int,
	marked_for_removal: bool,
}

// Serialized
Sort_Order :: enum {
	Descending,
	Ascending,
}

// Serialized
Track_Sort_Metric :: enum {
	None,
	Title,
	Artist,
	Album,
	Duration,
	Genre,
}

Track_Sort_Spec :: struct {
	metric: Track_Sort_Metric,
	order: Sort_Order,
}

Playlist :: struct {
	id: Playlist_ID,
	file_id: u32,
	name: cstring,
	tracks: [dynamic]u32,
}

Playlist_List :: struct {
	// Hashes of the group strings
	hashes: [dynamic]u32,
	playlists: [dynamic]Playlist,
}

Track_Data :: struct {
	paths: path_pool.Pool,
	path_ids: [dynamic]u32,
	metadata: [dynamic]Raw_Track_Info,
}

Library :: struct {
	paths: path_pool.Pool,
	track_path_hashes: [dynamic]u32,
	tracks: [dynamic]Raw_Track_Info,
	next_playlist_id: u32,
	playlists: [dynamic]Playlist,
	albums: Playlist_List,
	artists: Playlist_List,
	folders: Playlist_List,
	genres: Playlist_List,
	library: Playlist,
	playlist_dir: string,
}

init :: proc(playlist_folder: string) -> (lib: Library) {
	scan_for_playlists(&lib, playlist_folder)
	lib.playlist_dir = strings.clone(playlist_folder)
	lib.library.name = "Library"
	lib.next_playlist_id = 1
	return
}

destroy :: proc(lib: Library) {
	//_save_library("library.json")

	delete(lib.library.tracks)

	for p in lib.playlists {
		free_playlist(p)
	}

	delete(lib.track_path_hashes)
	delete(lib.tracks)
	delete(lib.playlists)
	delete(lib.playlist_dir)
	delete_playlist_list(lib.albums)
	delete_playlist_list(lib.genres)
	delete_playlist_list(lib.artists)
	delete_playlist_list(lib.folders)
	path_pool.destroy(lib.paths)
}


load :: proc(lib: ^Library, filename: string,) -> (ok: bool) {
	return _load_library(lib, filename)
}

scan_for_playlists :: proc(lib: ^Library, path: string) {
	walk_proc :: proc(fullpath: string, is_folder: bool, data: rawptr) {
		lib := cast(^Library) data
		log.debug("Load playlist", fullpath)

		playlist, playlist_ok := load_playlist_from_file(lib, fullpath)
		if !playlist_ok {return}
		playlist.id = _alloc_playlist_id(lib)

		file_id := strconv.parse_u64_maybe_prefixed(filepath.base(fullpath)) or_else 0
		if file_id == 0 {
			free_playlist(playlist)
			return
		}

		playlist.file_id = u32(file_id)
		append(&lib.playlists, playlist)

		return
	}

	util.for_each_file_in_folder("playlists", walk_proc, lib)
}

@private
_load_library :: proc(lib: ^Library, filename: string) -> (ok: bool) {
	timer: time.Stopwatch
	time.stopwatch_start(&timer)
	defer {
		time.stopwatch_stop(&timer)
		duration := time.stopwatch_duration(timer)
		log.debug("Load library:", time.duration_milliseconds(duration), "ms")
	}

	// Helper for getting json strings
	get_string :: proc(obj: json.Object, key: string) -> string {
		v, ok := obj[key]
		if !ok {return ""}
		return v.(json.String) or_else ""
	}

	get_int :: proc(obj: json.Object, key: string) -> int {
		v, ok := obj[key]
		if !ok {return 0}
		return cast(int) (v.(json.Integer) or_else 0)
	}

	// Read file
	file_data := os.read_entire_file_from_filename(filename) or_return
	defer delete(file_data)

	// Parse json
	root_value, parse_error := json.parse(file_data, .JSON5, parse_integers=true)
	if parse_error != .None {return}
	defer json.destroy_value(root_value)

	// Iterate tracks
	root := root_value.(json.Object) or_return
	tracks_value := root["tracks"] or_return
	tracks := tracks_value.(json.Array) or_return

	for track_value in tracks {
		track := track_value.(json.Object) or_continue
		path := get_string(track, "path")
		title := get_string(track, "title")
		album := get_string(track, "album")
		artist := get_string(track, "artist")
		genre := get_string(track, "genre")
		track_num := get_int(track, "track_num")
		year := get_int(track, "year")
		duration := get_int(track, "duration")
		bitrate := get_int(track, "bitrate")

		cleaned_path := filepath.clean(path) or_continue
		defer delete(cleaned_path)

		track_data: Raw_Track_Info
		track_data.path = path_pool.store(&lib.paths, path)
		util.copy_string_to_buf(track_data.title[:], title)
		util.copy_string_to_buf(track_data.artist[:], artist)
		util.copy_string_to_buf(track_data.album[:], album)
		util.copy_string_to_buf(track_data.genre[:], genre)
		track_data.track_number = track_num
		track_data.year = year
		track_data.duration_seconds = duration
		track_data.bitrate = bitrate

		_add_track(lib, cleaned_path, track_data)
	}

	ok = true
	return
}

save_to_file :: proc(lib: Library, filename: string) {
	write_kv_pair :: util.json_write_kv_pair

	file, open_error := util.overwrite_file(filename)
	if open_error != nil {return}
	
	fmt.fprintln(file, "{")
	defer fmt.fprintln(file, "}")

	fmt.fprintln(file, "\"tracks\": [")
	defer fmt.fprintln(file, "],")

	for track_id in lib.library.tracks {
		fmt.fprintln(file, "{")
		defer fmt.fprintln(file, "},")
		track := get_track_info(lib, track_id)
		if track.marked_for_removal {continue}
		track_path_buf: [512]u8
		track_path := get_track_path_cstring(lib, track_id, track_path_buf[:])
		write_kv_pair(file, "path", track_path)
		write_kv_pair(file, "title", track.title)
		write_kv_pair(file, "artist", track.artist)
		write_kv_pair(file, "album", track.album)
		write_kv_pair(file, "genre", track.genre)
		write_kv_pair(file, "duration", track.duration_seconds)
		write_kv_pair(file, "track", track.track_number)
		write_kv_pair(file, "year", track.year)
		write_kv_pair(file, "bitrate", track.bitrate)
	}
}

scan_folder :: proc(exclude_path_hashes: []u32, path: string, output: ^Track_Data) {
	dir, dir_error := os2.open(path)
	if dir_error != nil {return}
	files, read_error := os2.read_dir(dir, max(int), context.allocator)
	if read_error != nil {return}
	defer os2.file_info_slice_delete(files, context.allocator)

	for file in files {
		track: Raw_Track_Info

		path_id := xxhash.XXH32(transmute([]u8) file.fullpath)

		if file.type == .Directory {
			scan_folder(exclude_path_hashes, file.fullpath, output)
		}
		else if file.type == .Regular {
			if slice.contains(exclude_path_hashes, path_id) {continue}
			if !is_supported_format(file.fullpath) {continue}

			_read_track_metadata(&track, file.fullpath)
			track.path = path_pool.store(&output.paths, file.fullpath)

			append(&output.path_ids, path_id)
			append(&output.metadata, track)
		}
	}
}

free_track_data :: proc(data: Track_Data) {
	delete(data.metadata)
	delete(data.path_ids)
	path_pool.destroy(data.paths)
}

add_tracks_from_track_data :: proc(lib: ^Library, track_data: Track_Data) {
	outer_loop: for track_index in 0..<len(track_data.metadata) {
		path_buf: [512]u8
		track := track_data.metadata[track_index]
		path := path_pool.retrieve(track_data.paths, track.path, path_buf[:])
		_add_track(lib, path, track_data.metadata[track_index])

		log.debug("Add track:", cstring(&track.artist[0]), "-", cstring(&track.title[0]))
	}
}

@private
_add_track :: proc(lib: ^Library, path: string, metadata: Raw_Track_Info) -> Track_ID {
	path_hash := xxhash.XXH32(transmute([]u8)path)
	if slice.contains(lib.track_path_hashes[:], path_hash) {return 0}

	track := metadata
	track.path = path_pool.store(&lib.paths, path)
	dir_name := filepath.dir(path)
	defer delete(dir_name)
	
	id := cast(Track_ID) len(lib.tracks)+1

	append(&lib.track_path_hashes, path_hash)
	append(&lib.tracks, track)
	append(&lib.library.tracks, id)

	_add_to_playlist_group(id, string(cstring(&track.artist[0])), &lib.artists)
	_add_to_playlist_group(id, string(cstring(&track.album[0])), &lib.albums)
	_add_to_playlist_group(id, filepath.base(dir_name), &lib.folders)
	_add_to_playlist_group(id, string(cstring(&track.genre[0])), &lib.genres)

	return id
}

@private
_get_track_default_metadata :: proc(track: ^Raw_Track_Info, path: string) {
	filename := filepath.base(path)
	util.copy_string_to_buf(track.title[:], filename)
}

@private
_read_track_metadata :: proc(track: ^Raw_Track_Info, path: string) {
	path_cstring_buf: [384]u8
	file: taglib.File
	tag: taglib.Tag

	copy(path_cstring_buf[:383], path)
	path_cstring := cstring(raw_data(path_cstring_buf[:]))

	// Tracks must have a title or else the UI will crash (probably)
	defer assert(track.title[0] != 0)

	defer if file == nil || tag == nil {
		_get_track_default_metadata(track, path)
	}

	// @TODO: Use utf-16 string for Windows
	file = taglib.wrapped_open(path_cstring)
	if file == nil {
		log.error("Failed to read metadata from", filepath.base(path))
		return
	}
	defer taglib.file_free(file)

	tag = taglib.file_tag(file)
	defer taglib.tag_free_strings()

	audio_props := taglib.file_audioproperties(file)

	if tag != nil {
		title := taglib.tag_title(tag)

		if title == nil || len(title) == 0 {
			_get_track_default_metadata(track, path)
		}
		else {
			artist := taglib.tag_artist(tag)
			album := taglib.tag_album(tag)
			genre := taglib.tag_genre(tag)
			track_index := taglib.tag_track(tag)
			year := taglib.tag_year(tag)

			util.copy_cstring(track.title[:], title)
			util.copy_cstring(track.album[:], album)
			util.copy_cstring(track.artist[:], artist)
			util.copy_cstring(track.genre[:], genre)
			track.year = auto_cast year
			track.track_number = auto_cast track_index
		}
	}
	
	if audio_props != nil {
		track.duration_seconds = auto_cast taglib.audioproperties_length(audio_props)
	}
	
	if track.duration_seconds == 0 {
		// Try open the file for streaming to get the duration
		log.debug("Guessing duration of", filepath.base(path))
		dec: decoder.Decoder
		if decoder.open(&dec, path) {
			track.duration_seconds = decoder.get_duration(dec)
			if track.duration_seconds == 0 {
				log.error("Failed to guess duration of", filepath.base(path))
			}
			decoder.close(&dec)
		}
		else {
			log.error("Failed to open file", filepath.base(path))
		}
	}
}

is_supported_format :: proc(filename: string) -> bool {
	ext := filepath.ext(filename)

	return ext == ".mp3" ||
		ext == ".wav" ||
		ext == ".riff" ||
		ext == ".aiff" ||
		ext == ".flac" ||
		ext == ".ape" ||
		ext == ".opus"
}

remove_tracks :: proc(lib: ^Library, tracks: []Track_ID) {
	playlist_altered := make([]bool, len(lib.playlists))
	defer delete(playlist_altered)

	for track in tracks {
		if track == 0 {continue}
		track_index := track-1
		lib.tracks[track_index].marked_for_removal = true

		index_in_library, found_in_library := slice.linear_search(lib.library.tracks[:], track)
		if found_in_library {
			ordered_remove(&lib.library.tracks, index_in_library)
		}

		for &playlist, playlist_index in lib.playlists {
			index_in_playlist := slice.linear_search(playlist.tracks[:], track) or_continue
			ordered_remove(&playlist.tracks, index_in_playlist)
			playlist_altered[playlist_index] = true
		}
	}

	for playlist, playlist_index in lib.playlists {
		if playlist_altered[playlist_index] {
			save_playlist(lib^, playlist.id)
		}
	}
}

// Use to alter metadata of track
get_raw_track_info_pointer :: proc(lib: Library, track: Track_ID) -> ^Raw_Track_Info {
	assert(track != 0)
	return &lib.tracks[track-1]
}

get_track_info :: proc(lib: Library, track: Track_ID) -> Track_Info {
	assert(track != 0)
	info := &lib.tracks[track-1]
	return {
		id = track,
		title = cstring(&info.title[0]),
		artist = cstring(&info.artist[0]),
		album = cstring(&info.album[0]),
		genre = cstring(&info.genre[0]),
		bitrate = info.bitrate,
		duration_seconds = info.duration_seconds,
		track_number = info.track_number,
		year = info.year,
		marked_for_removal = info.marked_for_removal,
	}
}

refresh_track_metadata :: proc(lib: Library, track_id: Track_ID) {
	buf: [384]u8
	path := get_track_path(lib, track_id, buf[:])
	track := &lib.tracks[track_id-1]
	_read_track_metadata(track, path)
}

add_file :: proc(lib: ^Library, file: string) -> Track_ID {
	cleaned_path, err := filepath.clean(file)
	if err != .None {return 0}
	defer delete(cleaned_path)

	if !is_supported_format(file) {
		log.debug("~~~ Unsupported file format ~~~", filepath.ext(file))
		return 0
	}

	id := xxhash.XXH32(transmute([]u8) cleaned_path)

	// Check if the track is already in the library
	for iter_id, index in lib.track_path_hashes {
		if iter_id == id {
			return cast(Track_ID) (index+1)
		}
	}

	track: Raw_Track_Info

	_read_track_metadata(&track, file)

	return _add_track(lib, file, track)
}

get_playlist_group_id_from_name :: proc(group_string: string, case_insensitive := false) -> Playlist_ID {
	if case_insensitive {
		lower := strings.to_lower(group_string)
		defer delete(lower)
		return {user = 0, group = xxhash.XXH32(transmute([]u8)lower)}
	}
	else {
		return {user = 0, group = xxhash.XXH32(transmute([]u8)group_string)}
	}
}

@private
_add_to_playlist_group :: proc(track: Track_ID, group_string: string, group: ^Playlist_List, case_insensitive := false) {
	hash := get_playlist_group_id_from_name(group_string, case_insensitive).group

	for h, index in group.hashes {
		if h == hash {
			playlist_add_tracks(&group.playlists[index], {track})
			return
		}
	}

	playlist := Playlist {
		name = strings.clone_to_cstring(group_string),
		id = {group = hash},
	}

	append(&playlist.tracks, track)
	append(&group.hashes, hash)
	append(&group.playlists, playlist)
}

get_track_path :: proc(lib: Library, track: Track_ID, buf: []u8) -> string {
	if track == 0 {return ""}
	track_info := lib.tracks[track-1]
	return path_pool.retrieve(lib.paths, track_info.path, buf)
}

get_track_path_cstring :: proc(lib: Library, track: Track_ID, buf: []u8) -> cstring {
	if track == 0 {return nil}
	track_info := lib.tracks[track-1]
	return path_pool.retrieve_cstring(lib.paths, track_info.path, buf)
}

// =============================================================================
// Playlist management
// =============================================================================

@private
_playlist_file_id_is_used :: proc(lib: Library, id: u32) -> bool {
	for p in lib.playlists {
		if p.file_id == id {return true}
	}
	return false
}

@private
_alloc_playlist_id :: proc(lib: ^Library) -> (id: Playlist_ID) {
	id.user = lib.next_playlist_id
	lib.next_playlist_id += 1
	return id
}

add_playlist :: proc(lib: ^Library, name: string) -> (Playlist_ID, Add_Playlist_Error) {
	if name == "" {return {}, .EmptyName}

	for p in lib.playlists {
		if name == string(p.name) {
			return {}, .NameExists
		}
	}

	playlist := Playlist {
		name = strings.clone_to_cstring(name),
	}

	playlist.id = _alloc_playlist_id(lib)
	playlist.file_id = u32(rand.int31())
	for _playlist_file_id_is_used(lib^, playlist.file_id) {
		playlist.file_id = u32(rand.int31())
	}

	log.debug("New playlist", name, "; file ID =", playlist.file_id)

	append(&lib.playlists, playlist)
	return playlist.id, .None
}

//@FixMe
get_playlist_path :: proc(lib: Library, playlist: Playlist) -> string {
	name_buf: [16]u8
	name := fmt.bprint(name_buf[:], playlist.file_id)
	return filepath.join({lib.playlist_dir, "playlists", name})
}

save_playlist :: proc(lib: Library, id: Playlist_ID) {
	if id.user == 0 {return}

	for playlist in lib.playlists {
		if playlist.id == id {
			fullpath := get_playlist_path(lib, playlist)
			defer delete(fullpath)

			save_playlist_to_file(lib, playlist, fullpath)
		}
	}
}

delete_playlist :: proc(lib: ^Library, id: Playlist_ID) {
	for p, index in lib.playlists {
		if p.id == id {
			free_playlist(p)
			path := get_playlist_path(lib^, p)
			defer delete(path)
			os.remove(path)
			ordered_remove(&lib.playlists, index)
			return
		}
	}
}

@private
_filter_track_string :: proc(utf8_str: string, filter: []rune) -> bool {
	if len(utf8_str) == 0 {return false}

	str_rune_buf: [256]rune
	str := util.decode_utf8_to_runes(str_rune_buf[:], utf8_str)
	filter_len := len(filter)
	
	for s in 0..<len(str) {
		fail := false

		if s + filter_len >= len(str) {
			break
		}

		for f in 0..<len(filter) {
			if unicode.to_lower(str[s+f]) != unicode.to_lower(filter[f]) {
				fail = true
				break
			}
		}

		if !fail {return true}
	}

	return false
}

filter_track_from_runes :: proc(lib: Library, track: Track_Info, runes: []rune) -> bool {
	if _filter_track_string(string(track.title), runes) {
		return true
	}

	if _filter_track_string(string(track.artist), runes) {
		return true
	}
	
	if _filter_track_string(string(track.album), runes) {
		return true
	}
	
	if _filter_track_string(string(track.genre), runes) {
		return true
	}

	path_buf: [512]u8
	path := get_track_path(lib, track.id, path_buf[:])

	if _filter_track_string(path, runes) {
		return true
	}

	return false
}

filter_track_from_string :: proc(lib: Library, track: Track_Info, filter: string) -> bool {
	filter_rune_buf: [256]rune
	filter_runes := util.decode_utf8_to_runes(filter_rune_buf[:], filter)
	return filter_track_from_runes(lib, track, filter_runes)
}

filter_track :: proc {filter_track_from_string, filter_track_from_runes}

// WARNING: The returned pointer may be invalidated after a call
// to add_playlist or delete_playlist
get_playlist :: proc(lib: ^Library, id: Playlist_ID) -> ^Playlist {
	if id.user == 0 {
		return &lib.library
	}

	for &p in lib.playlists {
		if p.id == id {
			return &p
		}
	}

	return nil
}

// =============================================================================
// Metadata
// =============================================================================

Detailed_Metadata :: struct {
	buf: [4096]u8,
	comment: cstring,
}

load_track_thumbnail :: proc(lib: Library, track_id: Track_ID) -> (texture: video.Texture, ok: bool) {
	path_buf: [512]u8
	path := get_track_path_cstring(lib, track_id, path_buf[:])

	file := taglib.file_new(path)
	if file == nil {return}
	defer taglib.file_free(file)

	complex_props := taglib.complex_property_get(file, "PICTURE")
	if complex_props == nil {return}
	defer taglib.complex_property_free(complex_props)

	pic: taglib.Complex_Property_Picture_Data
	taglib.picture_from_complex_property(complex_props, &pic)

	if pic.data != nil {
		width, height: i32
		image_data := stbi.load_from_memory(pic.data, auto_cast pic.size, &width, &height, nil, 4)
		if image_data == nil {return}
		defer stbi.image_free(image_data)
		return video.impl.create_texture(auto_cast width, auto_cast height, image_data)
	}

	return
}

load_track_comment :: proc(lib: Library, track_id: Track_ID) -> cstring {
	path_buf: [512]u8
	path := get_track_path_cstring(lib, track_id, path_buf[:])

	file := taglib.file_new(path)
	if file == nil {return nil}
	defer taglib.file_free(file)

	tag := taglib.file_tag(file)
	if tag == nil {return nil}
	defer taglib.tag_free_strings()

	comment := taglib.tag_comment(tag)
	if comment != nil && len(comment) > 0 {
		length := len(comment)
		buf := make([]u8, length+1)
		buf[length] = 0
		copy(buf[:length], (cast([^]u8)comment)[:length])
		return cstring(raw_data(buf))
	}

	return nil
}

Metadata_Component :: enum {
	Title,
	Artist,
	Album,
	Genre,
}

Metadata_Replacement :: struct {
	replace: string,
	with: string,
	replace_mask: bit_set[Metadata_Component],
}

@private
_changed_tracks: [dynamic]Track_ID

@private
_save_track_metadata_to_file :: proc(lib: Library, track: ^Raw_Track_Info) {
	path_buf: [512]u8
	path := path_pool.retrieve_cstring(lib.paths, track.path, path_buf[:])

	file := taglib.wrapped_open(path)
	if file == nil {return}
	defer taglib.file_free(file)

	tag := taglib.file_tag(file)
	if tag == nil {return}
	defer taglib.tag_free_strings()

	taglib.tag_set_title(tag, cstring(&track.title[0]))
	taglib.tag_set_artist(tag, cstring(&track.artist[0]))
	taglib.tag_set_album(tag, cstring(&track.album[0]))
	taglib.tag_set_genre(tag, cstring(&track.genre[0]))
	taglib.tag_set_track(tag, auto_cast track.track_number)
	taglib.tag_set_year(tag, auto_cast track.year)
	//taglib.file_save(file);
}

save_track_metadata :: proc(lib: Library, track_id: Track_ID) {
	if track_id == 0 {
		return
	}
	track := &lib.tracks[track_id-1]
	_save_track_metadata_to_file(lib, track)
}

perform_metadata_replacement :: proc(lib: Library, op: Metadata_Replacement, filter: []Track_ID = nil) -> (replacement_count: int) {
	do_replacement :: proc(dst: []u8, replace: string, with: string) -> bool {
		str := string(cstring(&dst[0]))
		if strings.contains(str, replace) {
			res, allocated := strings.replace(str, replace, with, -1)
			if allocated {
				delete(res)
			}
			util.copy_string_to_buf(dst, res)
			log.debug(replace, with, res)
			return true
		}
		return false
	}

	for &track, index in lib.tracks {
		track_id := cast (Track_ID) (index + 1)
		changed := false
		if filter != nil && !slice.contains(filter, track_id) {
			continue
		}
		if .Title in op.replace_mask {
			if do_replacement(track.title[:], op.replace, op.with) {
				replacement_count += 1
				changed = true
			}
		}
		if .Artist in op.replace_mask {
			if do_replacement(track.artist[:], op.replace, op.with) {
				replacement_count += 1
				changed = true
			}
		}
		if .Album in op.replace_mask {
			if do_replacement(track.album[:], op.replace, op.with) {
				replacement_count += 1
				changed = true
			}
		}
		if .Genre in op.replace_mask {
			if do_replacement(track.genre[:], op.replace, op.with) {
				replacement_count += 1
				changed = true
			}
		}

		if changed && !slice.contains(_changed_tracks[:], track_id) {
			append(&_changed_tracks, track_id)
		}
	}

	log.debug("Replaced metadata on", replacement_count, "tracks")
	return
}

/*Metadata_Save_Job :: struct {
	tracks_completed: int,
	total_tracks: int,
	done: bool,
}

@private
_metadata_save_job: Metadata_Save_Job

save_metadata_thread_proc :: proc() {
	job := &_metadata_save_job

	for track_id in _changed_tracks {
		if track_id == 0 {continue}
		track := &this.tracks[track_id - 1]
		_save_track_metadata_to_file(track)
		job.tracks_completed += 1
	}

	delete(_changed_tracks)
	_changed_tracks = nil
	job.done = true
}

save_metadata_changes_async :: proc() -> ^Metadata_Save_Job {
	if len(_changed_tracks) == 0 {
		return nil
	}
	
	_metadata_save_job = Metadata_Save_Job {
		tracks_completed = 0,
		total_tracks = len(_changed_tracks),
		done = false,
	}
	thread.run(save_metadata_thread_proc)
	return &_metadata_save_job
}
*/
