#+private
package client

import "core:slice"

_Selection :: struct {
	playlist_id: Playlist_ID,
	tracks: [dynamic]Track_ID,
}

_selection_clear :: proc(sel: ^_Selection) {
	clear(&sel.tracks)
}

_selection_add :: proc(sel: ^_Selection, playlist: Playlist_ID, track: Track_ID) {
	if sel.playlist_id != playlist {
		clear(&sel.tracks)
		sel.playlist_id = playlist

		append(&sel.tracks, track)
	}
	else if !slice.contains(sel.tracks[:], track) {
		append(&sel.tracks, track)
	}
}

_selection_select_all :: proc(sel: ^_Selection, playlist: Playlist_ID, tracks: []Track_ID) {
	resize(&sel.tracks, len(tracks))
	sel.playlist_id = playlist
	copy(sel.tracks[:], tracks) 
}

_selection_extend :: proc(sel: ^_Selection, playlist: Playlist_ID, src: []Track_ID, to_track: Track_ID) -> bool {
	track_index := slice.linear_search(src, to_track) or_return

	select_forward: bool
	have_before, have_after: bool
	before, after: int
	after = max(int)

	// If we haven't selected any tracks in this playlist,
	// we can just select everything up to the track index
	// and return
	if sel.playlist_id != playlist || len(sel.tracks) == 0 {
		clear(&sel.tracks)
		sel.playlist_id = playlist

		for track in src[0:track_index+1] {
			append(&sel.tracks, track)
		}

		return true
	}

	for track in sel.tracks {
		index := slice.linear_search(src, track) or_continue
		if index < track_index {
			have_before = true
			before = max(before, index)
		}
		if index > track_index {
			have_after = true
			after = min(after, index)
		}
	}

	if !have_after && !have_before {
		select_forward = true
		before = 0
	}
	else if have_after && have_before {
		select_forward = (after - track_index) > (track_index - before)
	}
	else {
		select_forward = have_before
	}

	if select_forward {
		for track in src[before:track_index+1] {
			_selection_add(sel, playlist, track)
		}
	}
	else {
		for track in src[track_index:after+1] {
			_selection_add(sel, playlist, track)
		}
	}

	return true
}
