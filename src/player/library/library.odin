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
package library;

import "core:os";
import "core:log";
import "core:path/filepath";
import "core:hash/xxhash";
import "core:strings";
import "core:unicode";
import "core:math/rand";
import "core:fmt";
import "core:strconv";
import "core:encoding/json";
import "core:time";
import "core:mem";
import "core:sync";
import "core:thread";
import "core:slice";
import stbi "vendor:stb/image";

import "../path_pool";
import "../../bindings/taglib";
import "../util";
import "../system_paths";
import "../video";
import "../decoder";

Track_ID :: u32;
Playlist_ID :: u32;

Add_Playlist_Error :: enum {
	None,
	NameExists,
	NameReserved,
};

@private
Pool_String :: struct {
	offset, length: int,
};

MAX_TRACK_TITLE_LENGTH :: 127;
MAX_TRACK_ARTIST_LENGTH :: 63;
MAX_TRACK_ALBUM_LENGTH :: 63;
MAX_TRACK_GENRE_LENGTH :: 31;

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
};

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
};

// Serialized
Sort_Order :: enum {
	Descending,
	Ascending,
};

// Serialized
Playlist_Sort_Metric :: enum {
	None,
	Title,
	Artist,
	Album,
	Duration,
	Genre,
};

Playlist :: struct {
	id: Playlist_ID,
	file_id: u32,
	// If this playlist contains a track group, this
	// is the hash of the grouping string
	group_id: u32,
	name: cstring,
	tracks: [dynamic]u32,
	filter_tracks: [dynamic]int,
	filter_hash: u32,
	min_filter_index: int,
	max_filter_index: int,
	sort_metric: Playlist_Sort_Metric,
	sort_order: Sort_Order,
};

Playlist_List_Sort_Metric :: enum {
	None,
	Name,
	Length,
};

Playlist_List :: struct {
	// Hashes of the group strings
	hashes: [dynamic]u32,
	playlists: [dynamic]Playlist,
	filter_indices: [dynamic]i32,
	filter_hash: u32,
	min_filter_index: i32,
	max_filter_index: i32,
	sort_metric: Playlist_List_Sort_Metric,
	sort_order: Sort_Order,
};

@private
this: struct {
	paths: path_pool.Pool,
	track_ids: [dynamic]u32,
	tracks: [dynamic]Raw_Track_Info,
	metadata_pool: [dynamic]u8,
	next_playlist_id: Playlist_ID,
	playlists: [dynamic]Playlist,
	albums: Playlist_List,
	artists: Playlist_List,
	folders: Playlist_List,
	genres: Playlist_List,

	library: Playlist,
};

init :: proc() -> bool {	
	// Load library
	library_found: bool;

	library_path := filepath.join({system_paths.DATA_DIR, "library.json"});
	defer delete(library_path);
	_load_library(library_path);
	this.library.name = "Library";

	this.next_playlist_id = 1;
	_scan_playlist_folder();

	return true;
}

@private
_load_library :: proc(filename: string) -> bool {
	timer: time.Stopwatch;
	time.stopwatch_start(&timer);
	defer {
		time.stopwatch_stop(&timer);
		duration := time.stopwatch_duration(timer);
		log.debug("Load library:", time.duration_milliseconds(duration), "ms");
	}

	// Helper for getting json strings
	get_string :: proc(obj: json.Object, key: string) -> string {
		v, ok := obj[key];
		if !ok {return ""}
		return v.(json.String) or_else "";
	}

	get_int :: proc(obj: json.Object, key: string) -> int {
		v, ok := obj[key];
		if !ok {return 0}
		return cast(int) (v.(json.Integer) or_else 0);
	}

	// Read file
	file_data, file_ok := os.read_entire_file_from_filename(filename);
	if !file_ok {return false}
	defer delete(file_data);

	// Parse json
	root_value, parse_error := json.parse(file_data, .JSON5, parse_integers=true);
	if parse_error != .None {return false}
	defer json.destroy_value(root_value);

	// Iterate tracks
	root := root_value.(json.Object) or_return;
	tracks_value := root["tracks"] or_return;
	tracks := tracks_value.(json.Array) or_return;

	this.library.sort_metric = cast(Playlist_Sort_Metric) get_int(root, "sort_metric");
	this.library.sort_order = cast(Sort_Order) get_int(root, "sort_order");

	for track_value in tracks {
		track := track_value.(json.Object) or_continue;
		path := get_string(track, "path");
		title := get_string(track, "title");
		album := get_string(track, "album");
		artist := get_string(track, "artist");
		genre := get_string(track, "genre");
		track_num := get_int(track, "track_num");
		year := get_int(track, "year");
		duration := get_int(track, "duration");
		bitrate := get_int(track, "bitrate");

		cleaned_path := filepath.clean(path) or_continue;
		defer delete(cleaned_path);

		path_id := xxhash.XXH32(transmute([]u8) cleaned_path);
		track_id := cast(Track_ID) len(this.tracks) + 1;

		track_data: Raw_Track_Info;
		track_data.path = path_pool.store(&this.paths, path);
		util.copy_string_to_buf(track_data.title[:], title);
		util.copy_string_to_buf(track_data.artist[:], artist);
		util.copy_string_to_buf(track_data.album[:], album);
		util.copy_string_to_buf(track_data.genre[:], genre);
		track_data.track_number = track_num;
		track_data.year = year;
		track_data.duration_seconds = duration;
		track_data.bitrate = bitrate;

		append(&this.track_ids, path_id);
		append(&this.tracks, track_data);
		append(&this.library.tracks, track_id);

		_add_to_playlist_group(track_id, artist, &this.artists);
		_add_to_playlist_group(track_id, album, &this.albums);
		_add_to_playlist_group(track_id, filepath.base(filepath.dir(path)), &this.folders);
		_add_to_playlist_group(track_id, genre, &this.genres);
	}

	return true;
}

@private
_save_library :: proc(filename: string) {
	write_kv_pair :: util.json_write_kv_pair;

	file, open_error := util.overwrite_file(filename);
	if open_error != nil {return}
	
	fmt.fprintln(file, "{");
	defer fmt.fprintln(file, "}");

	write_kv_pair(file, "sort_order", int(this.library.sort_order));
	write_kv_pair(file, "sort_metric", int(this.library.sort_metric));

	fmt.fprintln(file, "\"tracks\": [");
	defer fmt.fprintln(file, "],");

	for track_id in this.library.tracks {
		fmt.fprintln(file, "{");
		defer fmt.fprintln(file, "},");
		track := get_track_info(track_id);
		if track.marked_for_removal {continue}
		track_path_buf: [512]u8;
		track_path := get_track_path_cstring(track_id, track_path_buf[:]);
		write_kv_pair(file, "path", track_path);
		write_kv_pair(file, "title", track.title);
		write_kv_pair(file, "artist", track.artist);
		write_kv_pair(file, "album", track.album);
		write_kv_pair(file, "genre", track.genre);
		write_kv_pair(file, "duration", track.duration_seconds);
		write_kv_pair(file, "track", track.track_number);
		write_kv_pair(file, "year", track.year);
		write_kv_pair(file, "bitrate", track.bitrate);
	}
}

shutdown :: proc() {
	_save_library("library.json");

	delete(this.library.tracks);

	for p in this.playlists {
		free_playlist(p);
	}

	delete(this.track_ids);
	delete(this.tracks);
	delete(this.playlists);
	delete(this.metadata_pool);
	path_pool.destroy(&this.paths);
}

@private
_store_string_native :: proc(str: string) -> Pool_String {
	if len(str) == 0 {return {}}

	ps := Pool_String {
		offset = len(this.metadata_pool),
		length = len(str),
	};

	append(&this.metadata_pool, str[:]);
	append(&this.metadata_pool, 0);

	return ps;
}

@private
_store_string :: proc(str: cstring) -> Pool_String {
	if str == nil || len(str) == 0 {return {}}

	md := Pool_String {
		offset = len(this.metadata_pool),
		length = len(str),
	};

	slice := (transmute([^]u8)str)[:md.length];

	for i in 0..<md.length {
		append(&this.metadata_pool, slice[i]);
	}

	append(&this.metadata_pool, 0);

	return md;
}

@private
_replace_or_store_string :: proc(orig: Pool_String, str: cstring) -> Pool_String {
	if str == nil || len(str) == 0 {return {}}
	if orig == {} {
		return _store_string(str);
	}

	length := len(str);
	if length <= orig.length {
		this.metadata_pool[orig.offset+length] = 0;
		copy(this.metadata_pool[orig.offset:], (cast([^]u8)str)[:length]);
		return {orig.offset, length};
	}

	return _store_string(str);
}

@private
_get_track_default_metadata :: proc(track: ^Raw_Track_Info, path: string) {
	filename := filepath.base(path);
	util.copy_string_to_buf(track.title[:], filename);
}

@private
_read_track_metadata :: proc(track: ^Raw_Track_Info, path: string) {
	path_cstring_buf: [384]u8;
	file: taglib.File;
	tag: taglib.Tag;

	copy(path_cstring_buf[:383], path);
	path_cstring := cstring(raw_data(path_cstring_buf[:]));

	// Tracks must have a title or else the UI will crash (probably)
	defer assert(track.title[0] != 0);

	defer if file == nil || tag == nil {
		_get_track_default_metadata(track, path);
	}

	// @TODO: Use utf-16 string for Windows
	file = taglib.wrapped_open(path_cstring);
	if file == nil {
		log.error("Failed to read metadata from", filepath.base(path));
		return;
	}
	defer taglib.file_free(file);

	tag = taglib.file_tag(file);
	defer taglib.tag_free_strings();

	audio_props := taglib.file_audioproperties(file);

	if tag != nil {
		title := taglib.tag_title(tag);

		if title == nil || len(title) == 0 {
			_get_track_default_metadata(track, path);
		}
		else {
			artist := taglib.tag_artist(tag);
			album := taglib.tag_album(tag);
			genre := taglib.tag_genre(tag);
			track_index := taglib.tag_track(tag);
			year := taglib.tag_year(tag);

			util.copy_cstring(track.title[:], title);
			util.copy_cstring(track.album[:], album);
			util.copy_cstring(track.artist[:], artist);
			util.copy_cstring(track.genre[:], genre);
			track.year = auto_cast year;
			track.track_number = auto_cast track_index;
		}
	}
	
	if audio_props != nil {
		track.duration_seconds = auto_cast taglib.audioproperties_length(audio_props);
	}
	
	if track.duration_seconds == 0 {
		// Try open the file for streaming to get the duration
		log.debug("Guessing duration of", filepath.base(path));
		dec: decoder.Decoder;
		if decoder.open(&dec, path) {
			track.duration_seconds = decoder.get_duration(&dec);
			if track.duration_seconds == 0 {
				log.error("Failed to guess duration of", filepath.base(path));
			}
			decoder.close(&dec);
		}
		else {
			log.error("Failed to open file", filepath.base(path));
		}
	}
}

@private
_get_metadata_cstring :: proc(md: Pool_String) -> cstring {
	if md.length == 0 {return nil;}
	return cstring(&this.metadata_pool[md.offset]);
}

is_supported_format :: proc(filename: string) -> bool {
	ext := filepath.ext(filename);

	return ext == ".mp3" ||
		ext == ".wav" ||
		ext == ".riff" ||
		ext == ".aiff" ||
		ext == ".flac" ||
		ext == ".ape" ||
		ext == ".opus";
}

remove_tracks :: proc(tracks: []Track_ID) {
	playlist_altered := make([]bool, len(this.playlists));
	defer delete(playlist_altered);

	for track in tracks {
		if track == 0 {continue}
		track_index := track-1;
		this.tracks[track_index].marked_for_removal = true;

		index_in_library, found_in_library := slice.linear_search(this.library.tracks[:], track);
		if found_in_library {
			ordered_remove(&this.library.tracks, index_in_library);
			playlist_make_dirty(&this.library);
		}

		for &playlist, playlist_index in this.playlists {
			index_in_playlist := slice.linear_search(playlist.tracks[:], track) or_continue;
			ordered_remove(&playlist.tracks, index_in_playlist);
			playlist_make_dirty(&playlist);
			playlist_altered[playlist_index] = true;
		}
	}

	for playlist, playlist_index in this.playlists {
		if playlist_altered[playlist_index] {
			save_playlist(playlist.id);
		}
	}
}

// Use to alter metadata of track
get_raw_track_info_pointer :: proc(track: Track_ID) -> ^Raw_Track_Info {
	assert(track != 0);
	return &this.tracks[track-1];
}

get_track_info :: proc(track: Track_ID) -> Track_Info {
	assert(track != 0);
	info := &this.tracks[track-1];
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
	};
}

refresh_track_metadata :: proc(track_id: Track_ID) {
	buf: [384]u8;
	path := get_track_path(track_id, buf[:]);
	track := &this.tracks[track_id-1];
	_read_track_metadata(track, path);
	info := get_track_info(track_id);
}

add_directory :: proc(path: string) -> (first: Track_ID, last: Track_ID, ok := true) {
	handle, error := os.open(path);
	if error != os.ERROR_NONE {return 0, 0, false;}
	defer os.close(handle);

	files, read_dir_error := os.read_dir(handle, 0);

	if read_dir_error != os.ERROR_NONE {return 0, 0, false;}

	defer os.file_info_slice_delete(files);

	first = cast(u32) len(this.tracks) + 1;
	count: u32 = 0;

	for f in files {
		if f.is_dir {
			add_directory(f.fullpath);
		}
		else {
			add_file(f.fullpath);
		}

		count += 1;
	}

	if count == 0 {return 0, 0, false;}

	last = first + count - 1;

	return;
}

add_file :: proc(file: string) -> Track_ID {
	cleaned_path, err := filepath.clean(file);
	if err != .None {return 0;}
	defer delete(cleaned_path);

	if !is_supported_format(file) {
		log.debug("~~~ Unsupported file format ~~~", filepath.ext(file));
		return 0;
	}

	id := xxhash.XXH32(transmute([]u8) cleaned_path);

	// Check if the track is already in the library
	for iter_id, index in this.track_ids {
		if iter_id == id {
			return cast(Track_ID) (index+1);
		}
	}

	track: Raw_Track_Info;
	index := cast(Track_ID) len(this.tracks);
	track.path = path_pool.store(&this.paths, file);

	_read_track_metadata(&track, file);

	append(&this.track_ids, id);
	append(&this.tracks, track);

	append(&this.library.tracks, index+1);

	_add_to_playlist_group(index+1, string(cstring(&track.artist[0])), &this.artists);
	_add_to_playlist_group(index+1, string(cstring(&track.album[0])), &this.albums);
	_add_to_playlist_group(index+1, string(cstring(&track.genre[0])), &this.genres, case_insensitive=true);
	_add_to_playlist_group(index+1, filepath.base(filepath.dir(file)), &this.folders);

	return index+1;
}

@private
_add_to_playlist_group :: proc(track: Track_ID, group_string: string, group: ^Playlist_List, case_insensitive := false) {
	hash: u32;

	if case_insensitive {
		lower := strings.to_lower(group_string);
		defer delete(lower);
		hash = xxhash.XXH32(transmute([]u8)lower);
	}
	else {
		hash = xxhash.XXH32(transmute([]u8)group_string);
	}

	for h, index in group.hashes {
		if h == hash {
			playlist_add_tracks(&group.playlists[index], {track});
			return;
		}
	}

	playlist := Playlist {
		name = strings.clone_to_cstring(group_string),
		group_id = hash,
	};

	append(&playlist.tracks, track);
	append(&group.hashes, hash);
	append(&group.playlists, playlist);
}

get_albums :: proc() -> ^Playlist_List {
	return &this.albums;
}

get_artists :: proc() -> ^Playlist_List {
	return &this.artists;
}

get_folders :: proc() -> ^Playlist_List {
	return &this.folders;
}

get_genres :: proc() -> ^Playlist_List {
	return &this.genres;
}

get_track_path :: proc(track: Track_ID, buf: []u8) -> string {
	if track == 0 {return "";}
	track_info := this.tracks[track-1];
	return path_pool.retrieve(&this.paths, track_info.path, buf);
}

get_track_path_cstring :: proc(track: Track_ID, buf: []u8) -> cstring {
	if track == 0 {return nil;}
	track_info := this.tracks[track-1];
	return path_pool.retrieve_cstring(&this.paths, track_info.path, buf);
}

// =============================================================================
// Playlist management
// =============================================================================

@private
_playlist_file_id_is_used :: proc(id: u32) -> bool {
	for p in this.playlists {
		if p.file_id == id {return true}
	}
	return false;
}

@private
_alloc_playlist_id :: proc() -> Playlist_ID {
	id := this.next_playlist_id;
	this.next_playlist_id += 1;
	return id;
}

add_playlist :: proc(name: string) -> (Playlist_ID, Add_Playlist_Error) {
	playlist := Playlist {
		name = strings.clone_to_cstring(name),
	};

	for p in this.playlists {
		if name == string(p.name) {
			delete(playlist.name);
			return 0, .NameExists;
		}
	}

	playlist.id = _alloc_playlist_id();
	playlist.file_id = u32(rand.int31());
	for _playlist_file_id_is_used(playlist.file_id) {
		playlist.file_id = u32(rand.int31());
	}

	log.debug("New playlist", name, "; file ID =", playlist.file_id);

	append(&this.playlists, playlist);
	return playlist.id, .None;
}

get_playlist_path :: proc(playlist: Playlist) -> string {
	name_buf: [16]u8;
	name := fmt.bprint(name_buf[:], playlist.file_id);
	return filepath.join({system_paths.DATA_DIR, "playlists", name});
}

save_playlist :: proc(id: Playlist_ID) {
	if id == 0 {return}
	playlist := get_playlist(id)^;
	fullpath := get_playlist_path(playlist);
	defer delete(fullpath);

	save_playlist_to_file(playlist, fullpath);
}

delete_playlist :: proc(id: Playlist_ID) {
	for p, index in this.playlists {
		if p.id == id {
			free_playlist(p);
			path := get_playlist_path(p);
			defer delete(path);
			os.remove(path);
			ordered_remove(&this.playlists, index);
			return;
		}
	}
}

@private
_scan_playlist_folder :: proc() {
	playlists_path := filepath.join({system_paths.DATA_DIR, "playlists"});
	defer delete(playlists_path);

	if !os.exists(playlists_path) {
		os.make_directory(playlists_path);
		return;
	}

	walk_proc :: proc(fullpath: string, is_folder: bool, _: rawptr) {
		log.debug("Load playlist", fullpath);

		playlist, playlist_ok := load_playlist_from_file(fullpath);
		if !playlist_ok {return}

		file_id := strconv.parse_u64_maybe_prefixed(filepath.base(fullpath)) or_else 0;
		if file_id == 0 {
			free_playlist(playlist);
			return;
		}

		playlist.file_id = u32(file_id);
		append(&this.playlists, playlist);

		return;
	}

	util.for_each_file_in_folder("playlists", walk_proc, nil);
}


@private
_decode_utf8_to_buffer :: proc(str: string, buf: []rune) -> []rune {
	n: int;
	m := len(buf);

	for r in str {
		if n >= m {
			break;
		}

		buf[n] = r;
		n += 1;
	}

	return buf[:n];
}

@private
_filter_track_string :: proc(utf8_str: string, filter: []rune) -> bool {
	if len(utf8_str) == 0 {return false}

	str_rune_buf: [256]rune;
	str := _decode_utf8_to_buffer(utf8_str, str_rune_buf[:]);
	filter_len := len(filter);
	
	i, j: int;

	for s in 0..<len(str) {
		fail := false;

		if s + filter_len >= len(str) {
			break;
		}

		for f in 0..<len(filter) {
			if unicode.to_lower(str[s+f]) != unicode.to_lower(filter[f]) {
				fail = true;
				break;
			}
		}

		if !fail {return true}
	}

	return false;
}

filter_track :: proc(track: Track_Info, filter: string) -> bool {
	filter_rune_buf: [256]rune;
	filter_runes := _decode_utf8_to_buffer(filter, filter_rune_buf[:]);
	
	if _filter_track_string(string(track.title), filter_runes) {
		return true;
	}

	if _filter_track_string(string(track.artist), filter_runes) {
		return true;
	}
	
	if _filter_track_string(string(track.album), filter_runes) {
		return true;
	}
	
	if _filter_track_string(string(track.genre), filter_runes) {
		return true;
	}

	path_buf: [512]u8;
	path := get_track_path(track.id, path_buf[:]);

	if _filter_track_string(path, filter_runes) {
		return true;
	}

	return false;
}

// WARNING: The returned pointer may be invalidated after a call
// to add_playlist or delete_playlist
get_playlist :: proc(id: Playlist_ID) -> ^Playlist {
	if id == 0 {
		return &this.library;
	}

	for &p in this.playlists {
		if p.id == id {
			return &p;
		}
	}

	return nil;
}

get_playlists :: proc() -> []Playlist {
	return this.playlists[:];
}

get_default_playlist :: proc() -> ^Playlist {
	return &this.library;
}

// =============================================================================
// Metadata
// =============================================================================

Detailed_Metadata :: struct {
	buf: [4096]u8,
	comment: cstring,
};

load_track_thumbnail :: proc(track_id: Track_ID) -> (texture: video.Texture, ok: bool) {
	path_buf: [512]u8;
	path := get_track_path_cstring(track_id, path_buf[:]);

	file := taglib.file_new(path);
	if file == nil {return}
	defer taglib.file_free(file);

	complex_props := taglib.complex_property_get(file, "PICTURE");
	if complex_props == nil {return}
	defer taglib.complex_property_free(complex_props);

	pic: taglib.Complex_Property_Picture_Data;
	taglib.picture_from_complex_property(complex_props, &pic);

	if pic.data != nil {
		width, height: i32;
		image_data := stbi.load_from_memory(pic.data, auto_cast pic.size, &width, &height, nil, 4);
		if image_data == nil {return}
		defer stbi.image_free(image_data);
		return video.impl.create_texture(auto_cast width, auto_cast height, image_data);
	}

	return;
}

load_track_comment :: proc(track_id: Track_ID) -> cstring {
	path_buf: [512]u8;
	path := get_track_path_cstring(track_id, path_buf[:]);

	file := taglib.file_new(path);
	if file == nil {return nil}
	defer taglib.file_free(file);

	tag := taglib.file_tag(file);
	if tag == nil {return nil}
	defer taglib.tag_free_strings();

	comment := taglib.tag_comment(tag);
	if comment != nil && len(comment) > 0 {
		length := len(comment);
		buf := make([]u8, length+1);
		buf[length] = 0;
		copy(buf[:length], (cast([^]u8)comment)[:length]);
		return cstring(raw_data(buf));
	}

	return nil;
}

Metadata_Component :: enum {
	Title,
	Artist,
	Album,
	Genre,
};

Metadata_Replacement :: struct {
	replace: string,
	with: string,
	replace_mask: bit_set[Metadata_Component],
};

@private
_changed_tracks: [dynamic]Track_ID;

@private
_save_track_metadata_to_file :: proc(track: ^Raw_Track_Info) {
	path_buf: [512]u8;
	path := path_pool.retrieve_cstring(&this.paths, track.path, path_buf[:]);

	file := taglib.wrapped_open(path);
	if file == nil {return}
	defer taglib.file_free(file);

	tag := taglib.file_tag(file);
	if tag == nil {return}
	defer taglib.tag_free_strings();

	taglib.tag_set_title(tag, cstring(&track.title[0]));
	taglib.tag_set_artist(tag, cstring(&track.artist[0]));
	taglib.tag_set_album(tag, cstring(&track.album[0]));
	taglib.tag_set_genre(tag, cstring(&track.genre[0]));
	taglib.tag_set_track(tag, auto_cast track.track_number);
	taglib.tag_set_year(tag, auto_cast track.year);
	//taglib.file_save(file);
}

save_track_metadata :: proc(track_id: Track_ID) {
	if track_id == 0 {
		return;
	}
	track := &this.tracks[track_id-1];
	_save_track_metadata_to_file(track);
}

perform_metadata_replacement :: proc(op: Metadata_Replacement, filter: []Track_ID = nil) -> (replacement_count: int) {
	do_replacement :: proc(dst: []u8, replace: string, with: string) -> bool {
		str := string(cstring(&dst[0]));
		if strings.contains(str, replace) {
			res, allocated := strings.replace(str, replace, with, -1);
			if allocated {
				delete(res);
			}
			util.copy_string_to_buf(dst, res);
			log.debug(replace, with, res);
			return true;
		}
		return false;
	}

	for &track, index in this.tracks {
		track_id := cast (Track_ID) (index + 1);
		changed := false;
		if filter != nil && !slice.contains(filter, track_id) {
			continue;
		}
		if .Title in op.replace_mask {
			if do_replacement(track.title[:], op.replace, op.with) {
				replacement_count += 1;
				changed = true;
			}
		}
		if .Artist in op.replace_mask {
			if do_replacement(track.artist[:], op.replace, op.with) {
				replacement_count += 1;
				changed = true;
			}
		}
		if .Album in op.replace_mask {
			if do_replacement(track.album[:], op.replace, op.with) {
				replacement_count += 1;
				changed = true;
			}
		}
		if .Genre in op.replace_mask {
			if do_replacement(track.genre[:], op.replace, op.with) {
				replacement_count += 1;
				changed = true;
			}
		}

		if changed && !slice.contains(_changed_tracks[:], track_id) {
			append(&_changed_tracks, track_id);
		}
	}

	log.debug("Replaced metadata on", replacement_count, "tracks");
	return;
}

Metadata_Save_Job :: struct {
	tracks_completed: int,
	total_tracks: int,
	done: bool,
};

@private
_metadata_save_job: Metadata_Save_Job;

save_metadata_thread_proc :: proc() {
	job := &_metadata_save_job;

	for track_id in _changed_tracks {
		if track_id == 0 {continue}
		track := &this.tracks[track_id - 1];
		_save_track_metadata_to_file(track);
		job.tracks_completed += 1;
	}

	delete(_changed_tracks);
	_changed_tracks = nil;
	job.done = true;
}

save_metadata_changes_async :: proc() -> ^Metadata_Save_Job {
	if len(_changed_tracks) == 0 {
		return nil;
	}
	
	_metadata_save_job = Metadata_Save_Job {
		tracks_completed = 0,
		total_tracks = len(_changed_tracks),
		done = false,
	};
	thread.run(save_metadata_thread_proc);
	return &_metadata_save_job;
}
