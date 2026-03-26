package main

import "core:math/rand"
import "core:slice"

Playback_Queue :: struct {
	tracks: [dynamic]Track_ID,
	pos: int,
	current_track: Maybe(Track_ID),
	playlist_uid: UID,
	serial: uint,
	enable_shuffle: bool,
}

playback_queue_set_pos :: proc(p: ^Playback_Queue, pos: int) -> (Track_ID, bool) {
	if len(p.tracks) == 0 do return {}, false

	p.pos = pos

	if p.pos < 0 do p.pos = 0
	if p.pos >= len(p.tracks) do p.pos = len(p.tracks) - p.pos

	return p.tracks[p.pos], true
}

playback_queue_clear :: proc(p: ^Playback_Queue) {
	clear(&p.tracks)
	p.playlist_uid = 0
}

playback_queue_prev :: proc(p: ^Playback_Queue) -> (Track_ID, bool) {
	return playback_queue_set_pos(p, p.pos - 1)
}

playback_queue_next :: proc(p: ^Playback_Queue) -> (Track_ID, bool) {
	return playback_queue_set_pos(p, p.pos + 1)
}

playback_queue_add :: proc(p: ^Playback_Queue, tracks: []Track_ID, from_playlist: UID) -> bool {
	if len(p.tracks) == 0 do p.playlist_uid = from_playlist
	else do p.playlist_uid = 0

	for track_id in tracks {
		if track_id == {} do continue

		if !slice.contains(p.tracks[:], track_id) {
			append(&p.tracks, track_id)
		}
	}

	p.serial += 1

	if p.enable_shuffle do rand.shuffle(p.tracks[:])

	return true
}

playback_queue_contains :: proc(p: ^Playback_Queue, track_id: Track_ID) -> bool {
	return slice.contains(p.tracks[:], track_id)
}

playback_queue_set_track :: proc(p: ^Playback_Queue, track_id: Track_ID) {
	for track in p.tracks {
		if track == track_id {
			playback_queue_set_pos(p, p.pos)
			return
		}
	}
}
