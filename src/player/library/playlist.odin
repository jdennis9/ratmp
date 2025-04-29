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

import "core:sort";
import "core:slice";
import "core:fmt";
import "core:os";
import "core:log";
import "core:strings";
import "core:time";
import "core:encoding/json";

import "../util";

save_playlist_to_file :: proc(playlist: Playlist, filename: string) {
	write_kv_pair :: util.json_write_kv_pair;

	file, error := util.overwrite_file(filename);
	if error != os.ERROR_NONE {return}
	defer os.close(file);

	fmt.fprintln(file, "{");
	write_kv_pair(file, "name", playlist.name);
	write_kv_pair(file, "sort_metric", int(playlist.sort_metric));
	write_kv_pair(file, "sort_order", int(playlist.sort_order));
	fmt.fprintln(file, "\"tracks\":[");
	for track_id in playlist.tracks {
		buf: [384]u8;
		buf_sanitized: [384]u8;
		path := get_track_path_cstring(track_id, buf[:]);
		sanitized := util.json_sanitize_string(path, buf_sanitized[:]);
		fmt.fprintln(file, "\"", sanitized, "\",", sep="", flush=false);
	}
	fmt.fprintln(file, "]");
	fmt.fprintln(file, "}");
}

load_playlist_from_file :: proc(filename: string) -> (playlist: Playlist, success: bool) {
	file_data, file_ok := os.read_entire_file_from_filename(filename);
	if !file_ok {return}
	defer delete(file_data);

	// Helper for getting json strings
	get_string :: proc(obj: json.Object, key: string) -> (string, bool) {
		v, ok := obj[key];
		if !ok {return "", false}
		#partial switch t in v {
			case json.String: {
				return t, true;
			}
		}
		return "", false;
	}

	get_int :: proc(obj: json.Object, key: string) -> int {
		v, ok := obj[key];
		if !ok {return 0}
		return cast(int) (v.(json.Integer) or_else 0);
	}

	root_value, parse_error := json.parse(file_data, .JSON5, parse_integers=true);
	if parse_error != .None {return}
	defer json.destroy_value(root_value);

	root := root_value.(json.Object) or_return;
	name := get_string(root, "name") or_return;
	tracks_value := root["tracks"] or_return;
	tracks := tracks_value.(json.Array) or_return;

	playlist.name = strings.clone_to_cstring(name);
	playlist.sort_metric = cast(Playlist_Sort_Metric) get_int(root, "sort_metric");
	playlist.sort_order = cast(Sort_Order) get_int(root, "sort_order");
	playlist.id = _alloc_playlist_id();

	for track_value in tracks {
		path := track_value.(json.String) or_continue;
		track_id := add_file(path);
		append(&playlist.tracks, track_id);
	}

	return playlist, true;
}

@private
free_playlist :: proc(p: Playlist) {
	delete(p.tracks);
	delete(p.name);
}

//@TODO: Detect when the playlist has changed since the last update
update_playlist_filter :: proc(playlist: ^Playlist, filter: string, filter_hash: u32) {
	if playlist.filter_hash != filter_hash {
		timer: time.Stopwatch;
		time.stopwatch_start(&timer);

		playlist.filter_hash = filter_hash;
		clear(&playlist.filter_tracks);

		log.debug("Refiltering playlist", playlist.name);

		playlist.min_filter_index = max(int);
		playlist.max_filter_index = 0;

		for track, track_index in playlist.tracks {
			if filter_track(get_track_info(track), filter) {
				append(&playlist.filter_tracks, track_index);
				playlist.min_filter_index = min(playlist.min_filter_index, track_index);
				playlist.max_filter_index = max(playlist.max_filter_index, track_index);
			}
		}

		time.stopwatch_stop(&timer);
		log.debug("Filter playlist:", time.duration_milliseconds(time.stopwatch_duration(timer)), "ms");
	}
}

sort_playlist :: proc(playlist: ^Playlist) {
	len_proc :: proc(iface: sort.Interface) -> int {
		return len((cast(^Playlist)iface.collection).tracks);
	}

	compare_title_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		playlist := cast(^Playlist)iface.collection;
		a := get_track_info(playlist.tracks[i]);
		b := get_track_info(playlist.tracks[j]);
		return strings.compare(string(a.title), string(b.title)) < 0;
	}

	compare_artist_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		playlist := cast(^Playlist)iface.collection;
		a := get_track_info(playlist.tracks[i]);
		b := get_track_info(playlist.tracks[j]);
		cmp := strings.compare(string(a.artist), string(b.artist));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.album), string(b.album));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.title), string(b.title));
		return cmp < 0;
	}

	compare_album_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		playlist := cast(^Playlist)iface.collection;
		a := get_track_info(playlist.tracks[i]);
		b := get_track_info(playlist.tracks[j]);
		cmp := strings.compare(string(a.album), string(b.album));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.artist), string(b.artist));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.title), string(b.title));
		return cmp < 0;
	}

	compare_duration_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		playlist := cast(^Playlist)iface.collection;
		a := get_track_info(playlist.tracks[i]);
		b := get_track_info(playlist.tracks[j]);
		if a.duration_seconds != b.duration_seconds {
			return a.duration_seconds < b.duration_seconds;
		}
		cmp := strings.compare(string(a.album), string(b.album));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.artist), string(b.artist));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.title), string(b.title));
		return cmp < 0;
	}

	compare_genre_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		playlist := cast(^Playlist)iface.collection;
		a := get_track_info(playlist.tracks[i]);
		b := get_track_info(playlist.tracks[j]);
		cmp := strings.compare(string(a.genre), string(b.genre));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.album), string(b.album));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.artist), string(b.artist));
		if cmp != 0 {return cmp < 0}
		cmp = strings.compare(string(a.title), string(b.title));
		return cmp < 0;
	}

	swap_proc :: proc(iface: sort.Interface, i, j: int) {
		playlist := cast(^Playlist)iface.collection;
		temp := playlist.tracks[i];
		playlist.tracks[i] = playlist.tracks[j];
		playlist.tracks[j] = temp;
	}

	iface: sort.Interface;
	iface.collection = playlist;
	iface.len = len_proc;
	switch playlist.sort_metric {
		case .None: {return}
		case .Title: {iface.less = compare_title_proc}
		case .Album: {iface.less = compare_album_proc}
		case .Artist: {iface.less = compare_artist_proc}
		case .Duration: {iface.less = compare_duration_proc}
		case .Genre: {iface.less = compare_genre_proc}
	}
	iface.swap = swap_proc;

	if playlist.sort_order == .Ascending {sort.sort(iface)}
	else {sort.reverse_sort(iface)}

	playlist_make_dirty(playlist);
}

playlist_make_dirty :: proc(playlist: ^Playlist) {
	playlist.filter_hash = 0;
}

playlist_clear :: proc(playlist: ^Playlist) {
	clear(&playlist.tracks);
	playlist_make_dirty(playlist);
}

playlist_add_tracks :: proc(playlist: ^Playlist, tracks: []Track_ID, and_sort := true) {
	for track in tracks {
		//if !slice.contains(playlist.tracks[:], track) {
			append(&playlist.tracks, track);
		//}
	}
	playlist_make_dirty(playlist);
	if and_sort {sort_playlist(playlist)}
}
