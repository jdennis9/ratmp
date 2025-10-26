package server

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
	constructors: sa.Small_Array(MAX_AUTO_PLAYLIST_PARAMS, Playlist_Auto_Build_Param),
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

playlist_build_from_auto_params :: proc(playlist: ^Playlist, lib: Library) {
	assert(playlist.auto_build_params != nil)
	ap := &playlist.auto_build_params.?

	clear(&playlist.tracks)
	playlist.duration = 0
	playlist.serial += 1
	ap.build_serial = lib.serial

	add_from_category :: proc(playlist: ^Playlist, lib: Library, cat: Track_Category, filter: string) -> (added: int, duration: i64) {
		ap := playlist.auto_build_params
		for entry in cat.entries {
			if string(entry.name) == filter {
				added = len(entry.tracks)
				for track_id in entry.tracks {
					if !slice.contains(playlist.tracks[:], track_id) {
						append(&playlist.tracks, track_id)
						track := library_find_track(lib, track_id) or_break
						duration += track.properties[.Duration].(i64) or_else 0
					}
				}
				return
			}
		}

		return
	}

	for &ctor, ctor_index in sa.slice(&ap.constructors) {
		duration: i64
		arg := string(cstring(&ctor.arg[0]))

		switch ctor.type {
			case .Artist:
				ap.track_count_by_constructor[ctor_index], duration = add_from_category(
					playlist, lib, lib.categories.artists, arg
				)
			case .Album:
				ap.track_count_by_constructor[ctor_index], duration = add_from_category(
					playlist, lib, lib.categories.albums, arg
				)
			case .Genre:
				ap.track_count_by_constructor[ctor_index], duration = add_from_category(
					playlist, lib, lib.categories.genres, arg
				)
			case .Filter:
				spec := Track_Filter_Spec{
					filter = arg,
					components = ~{},
				}
				filter_tracks(lib, spec, library_get_all_track_ids(lib), &playlist.tracks)
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
