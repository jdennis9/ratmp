package main

import hm "core:container/handle_map"
import "core:slice"

Playlist_Handle :: hm.Handle32

Playlist :: struct {
	handle: Playlist_Handle,
	uid: UID,
	name: string,
	name_cstring: cstring,
	tracks: [dynamic]Track_ID,
	serial: uint,
}

playlist_add :: proc(sv: ^Server, pl: ^Playlist, tracks: []Track_ID) {
	for track_id in tracks {
		if slice.contains(pl.tracks[:], track_id) do continue
		track := get_track(sv, track_id) or_continue
		append(&pl.tracks, track_id)
	}

	pl.serial += 1
}

playlist_remove :: proc(sv: ^Server, pl: ^Playlist, tracks: []Track_ID) {
	need_recalc_duration := false

	for track_id in tracks {
		index := slice.linear_search(pl.tracks[:], track_id) or_continue
		track, track_found := get_track(sv, track_id)
		ordered_remove(&pl.tracks, index)
	}

	pl.serial += 1
}
