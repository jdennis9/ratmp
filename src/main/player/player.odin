package player

import "src:main/decoder"
import "core:sync"
import "core:math/rand"
import "core:slice"
import "src:main/shared"
import "src:dsp"
import lib "src:main/library"

Repeat_Mode :: enum {
	Playlist,
	Track,
	None,
}

Config :: struct {
	no_audio: bool,
}

State :: struct {
	stopped:     bool,
	paused:      bool,
	shuffle_on:  bool,
	repeat_mode: Repeat_Mode,
	track:       Maybe(lib.Track_ID),
	playlist:    shared.UID,
}

Player :: struct {
	lock:                       sync.Mutex,
	queue:                      [dynamic]lib.Track_ID,
	queue_lock:                 sync.Mutex,
	queue_serial:               uint,
	playing_playlist_id:        shared.UID,
	playing_track_id:           Maybe(lib.Track_ID),
	playing_track_info:         decoder.Info,
	queue_pos:                  int,
	queue_is_shuffled:          bool,
	enable_shuffle:             bool,
	playback_thread:            Playback_Thread,
	output_rings:               [AUDIO_MAX_CHANNELS]Ring_Buffer(f32),
	output_intermediate_buffer: [AUDIO_MAX_CHANNELS][dynamic]f32,
	repeat_mode:                Repeat_Mode,
}

@(private="file")
_player: Player

@(private="file")
_audio_callback :: proc(
	_:     rawptr,
	event: Audio_Callback_Event,
	data:  []f32,
	spec:  Audio_Spec
) -> Audio_Callback_Status {
	p := &_player

	lock()
	defer unlock()

	switch event {
	case .Stream:
		output_buf: [AUDIO_MAX_CHANNELS][]f32
		frame_count := len(data) / spec.channels
		
		for ch in 0..<spec.channels {
			resize(&p.output_intermediate_buffer[ch], frame_count)
			output_buf[ch] = p.output_intermediate_buffer[ch][:]
		}
		
		status := playback_thread_request_frames(&p.playback_thread, output_buf[:spec.channels], spec.samplerate)

		if status == .Eof do return .Finish

		dsp.interlace(output_buf[:spec.channels], data)

		for ch in 0..<spec.channels {
			shared.rb_produce(&p.output_rings[ch], output_buf[ch])
		}

	case .BufferDropped:
	case .Paused:
	case .Resumed:
	case .TrackFinished:
		play_next_track(immediate = false)
	}

	return .Continue
}

init :: proc(cfg: Config) -> shared.Error {
	p := &_player

	if !cfg.no_audio {
		when ODIN_OS == .Windows do audio_init_wasapi() or_return
		else when ODIN_OS == .Linux do audio_init_pulse() or_return
	}
	else {
		audio_init_null()
	}

	audio_set_callback(_audio_callback, nil)
	audio_start() or_return

	playback_thread_init(&p.playback_thread, context.allocator)

	return nil
}

shutdown :: proc() {
	p := &_player
	delete(p.queue)

	playback_thread_destroy(&p.playback_thread)
	audio_shutdown()

	_player = {}
}

lock :: proc() {sync.lock(&_player.lock)}
unlock :: proc() {sync.unlock(&_player.lock)}

get_state :: proc() -> State {
	p := &_player

	return State {
		paused      = audio_is_paused(),
		repeat_mode = p.repeat_mode,
		shuffle_on  = p.enable_shuffle,
		stopped     = !playback_thread_has_track(p.playback_thread),
		track       = p.playing_track_id,
		playlist    = p.playing_playlist_id,
	}
}

get_current_track :: proc() -> Maybe(lib.Track_ID) {
	return _player.playing_track_id
}

get_current_playlist :: proc() -> shared.UID {
	return _player.playing_playlist_id
}

get_queue :: proc() -> []lib.Track_ID {
	return _player.queue[:]
}

get_queue_serial :: proc() -> uint {
	return _player.queue_serial
}

set_paused :: proc(paused: bool) {
	if paused {
		if !audio_is_paused() do audio_pause()
	}
	else {
		if audio_is_paused() do audio_resume()
	}
}

is_shuffle_on :: proc() -> bool {return _player.enable_shuffle}
set_shuffle_on :: proc(on: bool) {
	p := &_player
	p.enable_shuffle = on

	if on && !p.queue_is_shuffled {
		rand.shuffle(p.queue[:])
	}
}

get_playback_pos :: proc() -> int {
	return playback_thread_get_track_position(&_player.playback_thread)
}

seek :: proc(pos: int) {
	playback_thread_seek(&_player.playback_thread, pos)
	audio_drop_buffer()
}

get_track_info :: proc() -> decoder.Info {
	return _player.playing_track_info
}
clear_queue :: proc() {
	p := &_player
	sync.guard(&p.queue_lock)
	clear(&p.queue)
}

add_to_queue :: proc(tracks: []lib.Track_ID, playlist_uid: shared.UID, assume_unique := false) {
	p := &_player

	sync.guard(&p.queue_lock)

	if len(p.queue) == 0 do p.playing_playlist_id = playlist_uid
	else do p.playing_playlist_id = 0

	for track_id in tracks {
		if track_id == {} do continue

		if assume_unique || !slice.contains(p.queue[:], track_id) {
			append(&p.queue, track_id)
		}
	}

	if p.enable_shuffle {
		rand.shuffle(p.queue[:])
		p.queue_is_shuffled = true
	}
	else do p.queue_is_shuffled = false

	p.queue_serial += 1
}

set_queue_pos :: proc(pos: int, immediate: bool = true) -> (ok: bool) {
	p := &_player

	defer if !ok do stop_playback()

	if len(p.queue) == 0 do return
	p.queue_pos = pos

	p.queue_pos = max(p.queue_pos, 0)
	if p.queue_pos >= len(p.queue) {
		if p.repeat_mode == .None do return
		p.queue_pos = len(p.queue) - p.queue_pos
	}

	play_track(p.queue[p.queue_pos]) or_return

	if immediate do audio_drop_buffer()

	return true
}

play_url :: proc(url: string) -> bool {
	p := &_player
	p.playing_track_id = nil
	p.playing_playlist_id = 0

	return playback_thread_load_track(&p.playback_thread, url, &p.playing_track_info)
}

play_track :: proc(track_id: lib.Track_ID) -> bool {
	p := &_player
	track := lib.get_track(track_id) or_return
	playback_thread_load_track(&p.playback_thread, track.url, &p.playing_track_info) or_return

	set_paused(false)
	p.playing_track_id = track_id

	return true
}

play_next_track :: proc(immediate: bool = true) -> bool {
	p := &_player
	return set_queue_pos(p.queue_pos + 1, immediate)
}

play_prev_track :: proc(immediate: bool = true) -> bool {
	p := &_player
	return set_queue_pos(p.queue_pos - 1, immediate)
}

play_playlist :: proc(tracks: []lib.Track_ID, uid: shared.UID, initial_track: Maybe(lib.Track_ID) = nil) {
	p := &_player
	clear(&p.queue)
	add_to_queue(tracks, uid, assume_unique = true)

	if initial_track != nil {
		for track, i in p.queue {
			if track == initial_track.? {
				set_queue_pos(i)
			}
		}
	}
	else {
		set_queue_pos(0)
	}
}

stop_playback :: proc() {
	p := &_player
	p.playing_track_id = nil
	p.playing_playlist_id = 0
	clear(&p.queue)
	set_paused(true)
	playback_thread_close_track(&p.playback_thread)
}
