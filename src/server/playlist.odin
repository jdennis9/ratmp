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

import "core:strings"
import "core:slice"
import "core:sort"
import "core:time"

// Do not edit outside of playlist_ procs
Playlist :: struct {
	name: cstring,
	// nil if the playlist has not been loaded from a file
	src_path: string,
	duration: i64,
	time_created: i64,
	id: Playlist_ID,
	tracks: [dynamic]Track_ID,
	serial: uint,
	dirty: bool,
}

Playlist_Sort_Metric :: enum {
	Name,
	Duration,
	Length,
}

Playlist_Sort_Spec :: struct {
	metric: Playlist_Sort_Metric,
	order: Sort_Order,
}

playlist_init :: proc(playlist: ^Playlist, name: string, id: Playlist_ID) {
	if name != "" {
		playlist.name = strings.clone_to_cstring(string(name))
	}
	playlist.id = id
	playlist.time_created = time.to_unix_seconds(time.now())
}

playlist_set_name :: proc(playlist: ^Playlist, name: string) {
	delete(playlist.name)
	playlist.name = strings.clone_to_cstring(name)
}

playlist_destroy :: proc(playlist: ^Playlist) {
	delete(playlist.src_path)
	delete(playlist.tracks)
	delete(playlist.name)
	playlist^ = {}
}

playlist_add_tracks :: proc(playlist: ^Playlist, lib: Library, tracks: []Track_ID) {
	for track_id in tracks {
		track := library_find_track(lib, track_id) or_continue
		playlist_add_track(playlist, track)
	}
	playlist.serial += 1
}

playlist_add_track :: proc(playlist: ^Playlist, track: Track, assume_unique := false) {
	if assume_unique || !slice.contains(playlist.tracks[:], track.id) {
		append(&playlist.tracks, track.id)
		playlist.dirty = true
		playlist.duration += track.properties[.Duration].(i64) or_else 0
	}
	playlist.serial += 1
}

playlist_remove_tracks :: proc(playlist: ^Playlist, lib: Library, tracks: []Track_ID) {
	for track_id in tracks {
		track := library_find_track(lib, track_id) or_continue
		index_in_playlist := slice.linear_search(playlist.tracks[:], track_id) or_continue
		playlist.duration -= track.properties[.Duration].(i64) or_else 0
		ordered_remove(&playlist.tracks, index_in_playlist)
	}
	playlist.serial += 1
	playlist.dirty = true
}

playlist_sort :: proc(playlist: ^Playlist, lib: Library, spec: Track_Sort_Spec) {
	library_sort_tracks(lib, playlist.tracks[:], spec)
	playlist.serial += 1
}

sort_playlists :: proc(playlists_arg: []Playlist, spec: Playlist_Sort_Spec) {
	playlists := playlists_arg

	compare_name :: proc(it: sort.Interface, a, b: int) -> bool {
		playlists := cast(^[]Playlist)it.collection
		return strings.compare(string(playlists[a].name), string(playlists[b].name)) < 0
	}

	compare_duration :: proc(it: sort.Interface, a, b: int) -> bool {
		playlists := cast(^[]Playlist)it.collection
		return playlists[a].duration < playlists[b].duration
	}

	compare_length :: proc(it: sort.Interface, a, b: int) -> bool {
		playlists := cast(^[]Playlist)it.collection
		return len(playlists[a].tracks) < len(playlists[b].tracks)
	}

	len_proc :: proc(it: sort.Interface) -> int {
		playlists := cast(^[]Playlist)it.collection
		return len(playlists)
	}

	swap_proc :: proc(it: sort.Interface, a, b: int) {
		playlists := cast(^[]Playlist)it.collection
		temp := playlists[a]
		playlists[a] = playlists[b]
		playlists[b] = temp
	}

	it: sort.Interface
	it.collection = &playlists
	it.len = len_proc
	it.swap = swap_proc

	switch spec.metric {
		case .Name: it.less = compare_name
		case .Duration: it.less = compare_duration
		case .Length: it.less = compare_length
	}

	switch spec.order {
		case .Ascending: sort.sort(it)
		case .Descending: sort.reverse_sort(it)
	}
}
