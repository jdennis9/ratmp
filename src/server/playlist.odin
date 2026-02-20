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
package server

import "core:strings"
import "core:slice"

import sa "core:container/small_array"

MAX_AUTO_PLAYLIST_PARAMS :: 8

Playlist_Auto_Build_Param_Type :: enum u8 {
	Artist,
	Genre,
	Album,
	Filter,
	Folder,
}

Playlist_Auto_Build_Param :: struct {
	type: Playlist_Auto_Build_Param_Type,
	arg: [63]u8,
}

Playlist_Auto_Build_Params :: struct {
	params: sa.Small_Array(MAX_AUTO_PLAYLIST_PARAMS, Playlist_Auto_Build_Param),
	track_count_by_constructor: [MAX_AUTO_PLAYLIST_PARAMS]int,
	string_allocator: Allocator,
	build_serial: uint,
}

Playlist :: struct {
	id: Playlist_ID,
	origin: Playlist_Origin,
	name: string,
	name_cstring: cstring,
	src_path: string,
	duration: i64,
	tracks: [dynamic]Track_ID,
	serial: uint,
	saved_serial: uint,
	auto_build_params: Maybe(Playlist_Auto_Build_Params),
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

playlist_build_from_auto_params :: proc(playlist: ^Playlist, lib: ^Library) {
	assert(playlist.auto_build_params != nil)
	ap := &playlist.auto_build_params.?

	clear(&playlist.tracks)
	playlist.duration = 0
	playlist.serial += 1
	ap.build_serial = lib.serial

	add_from_category :: proc(
		playlist: ^Playlist, lib: Library, cat: ^Track_Category, filter: string
	) -> (added: int, duration: i64, found: bool) {
		hash := library_hash_string(filter)
		entry_index := track_category_find_entry_index(cat, hash) or_return
		entry := &cat.entries[entry_index]
		for track_id in entry.tracks {
			if !slice.contains(playlist.tracks[:], track_id) {
				append(&playlist.tracks, track_id)
				added += 1
				track := library_find_track(lib, track_id) or_continue
				duration += track.properties[.Duration].(i64) or_else 0
			}
		}

		found = true
		return
	}

	for &ctor, ctor_index in sa.slice(&ap.params) {
		duration: i64
		arg := string(cstring(&ctor.arg[0]))

		switch ctor.type {
			case .Artist:
				ap.track_count_by_constructor[ctor_index], duration, _ = add_from_category(
					playlist, lib^, &lib.categories.artists, arg
				)
			case .Album:
				ap.track_count_by_constructor[ctor_index], duration, _ = add_from_category(
					playlist, lib^,&lib.categories.albums, arg
				)
			case .Genre:
				ap.track_count_by_constructor[ctor_index], duration, _ = add_from_category(
					playlist, lib^, &lib.categories.genres, arg
				)
			case .Filter:
				spec := Track_Filter_Spec{
					filter = arg,
					components = ~{},
				}
				filter_tracks(lib^, spec, library_get_all_track_ids(lib^), &playlist.tracks)
			case .Folder:
				/*id, found := library_folder_tree_find_folder_by_name(lib, ctor.arg)
				if found {

				}*/
		}

		playlist.duration += duration
	}
}

playlist_add_tracks :: proc(playlist: ^Playlist, lib: ^Library, tracks: []Track_ID, assume_unique := false) {
	for track_id in tracks {
		if assume_unique || !slice.contains(playlist.tracks[:], track_id) {
			track := library_find_track(lib^, track_id) or_continue
			append(&playlist.tracks, track_id)
			playlist.duration += track.properties[.Duration].(i64) or_else 0
		}
	}
	playlist.serial += 1
	lib.playlists_serial += 1
}

playlist_remove_tracks :: proc(playlist: ^Playlist, lib: ^Library, tracks: []Track_ID) {
	for track in tracks {
		index := slice.linear_search(playlist.tracks[:], track) or_continue
		ordered_remove(&playlist.tracks, index)
	}

	playlist.serial += 1
	lib.playlists_serial += 1
}

playlist_add_auto_build_param :: proc(playlist: ^Playlist, lib: ^Library, type: Playlist_Auto_Build_Param_Type, arg: string) {
	param: Playlist_Auto_Build_Param

	if playlist.auto_build_params == nil {return}
	ap := &playlist.auto_build_params.?

	param.type = type
	copy(param.arg[:len(param.arg)-1], arg)

	sa.append(&ap.params, param)

	ap.build_serial = 0
	playlist.serial += 1
	lib.playlists_serial += 1
}

playlist_mark_dirty :: proc(playlist: ^Playlist, lib: ^Library) {
	playlist.serial += 1
	lib.playlists_serial += 1
	if playlist.auto_build_params != nil {
		ap := &playlist.auto_build_params.?
		ap.build_serial = 0
	}
}

playlist_set_name :: proc(playlist: ^Playlist, name: string) {
	playlist.name_cstring = strings.clone_to_cstring(name)
	playlist.name = string(playlist.name_cstring)
}

playlist_sort :: proc(playlist: ^Playlist, lib: Library, spec: Track_Sort_Spec) {
	library_sort_tracks(lib, playlist.tracks[:], spec)
	playlist.serial += 1
}
