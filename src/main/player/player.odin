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
package player

import "core:time"
import "core:log"
import "src:bindings/ffmpeg"
import "core:math/linalg"
import "core:reflect"
import "core:strconv"
import "src:main/decoder"
import "core:sync"
import "core:math/rand"
import "core:slice"
import "src:main/shared"
import "src:dsp"
import lib "src:main/library"

ANALYSIS_SAMPLERATE :: 48000
MAX_CHANNELS :: AUDIO_MAX_CHANNELS

Repeat_Mode :: enum {
	Playlist,
	Track,
	None,
}

Init_Config :: struct {
	no_audio:  bool,
	wake_proc: proc(),
}

ReplayGain_Mode :: enum {Track, Album,}

Config :: struct {
	enable_replaygain:     bool,
	replaygain_pregain:    f32,
	replaygain_preference: ReplayGain_Mode,
}

CONFIG_DEFAULTS :: Config {
	enable_replaygain     = true,
	replaygain_pregain    = 3,
	replaygain_preference = .Track,
}

State :: struct {
	stopped:     bool,
	paused:      bool,
	shuffle_on:  bool,
	repeat_mode: Repeat_Mode,
	track:       Maybe(lib.Track_ID),
	playlist:    shared.UID,
}

Play_Pause_Event :: struct {
	pause: bool,
}

Stop_Event :: struct {}

Skip_Track_Event :: struct {
	backwards: bool,
	immediate: bool,
}

Add_To_Queue_Event :: struct {
	tracks:        []lib.Track_ID,
	assume_unique: bool,
	from_playlist: shared.UID,
}

Remove_From_Queue_Event :: struct {
	tracks: []lib.Track_ID,
}

Clear_Queue_Event :: struct {}

Play_Playlist_Event :: struct {
	tracks:        []lib.Track_ID,
	uid:           shared.UID,
	initial_track: Maybe(lib.Track_ID),
}

Play_Track_Event :: struct {
	id: lib.Track_ID,
}

Set_Queue_Pos_Event :: struct {
	pos:       int,
	immediate: bool,
}

Set_Paused_Event :: struct {
	paused: bool,
}

Buffer_Filled_Event :: struct {}

// Needs to exist because pausing is done asynchronously. When the audio system actually
// gets paused a signal is sent to the audio callback which then sends this event.
Pause_State_Changed_Event :: struct {}

Event :: union {
	Set_Paused_Event,
	Play_Pause_Event,
	Stop_Event,
	Skip_Track_Event,
	Add_To_Queue_Event,
	Remove_From_Queue_Event,
	Clear_Queue_Event,
	Play_Playlist_Event,
	Play_Track_Event,
	Set_Queue_Pos_Event,
	Pause_State_Changed_Event,
	Buffer_Filled_Event,
}

Player :: struct {
	event_queue:                shared.Event_Queue(Event),
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
	output_intermediate_buffer: [AUDIO_MAX_CHANNELS][dynamic]f32,
	repeat_mode:                Repeat_Mode,
	config:                     Config,
	analysis:                   Analysis_Buffer,
}

@(private="file")
_player: Player

@(private="file")
_audio_callback :: proc(
	_:     rawptr,
	event: Audio_Callback_Event,
	data:  []f32,
	spec:  Audio_Spec
) -> (result: Audio_Callback_Status = .Continue) {
	p := &_player

	lock()
	defer unlock()

	switch event {
	case .Stream:
		if !playback_thread_has_track(p.playback_thread) {
			slice.zero(data)
			break
		}

		output_buf: [AUDIO_MAX_CHANNELS][]f32
		frame_count := len(data) / spec.channels
		
		for ch in 0..<spec.channels {
			resize(&p.output_intermediate_buffer[ch], frame_count)
			output_buf[ch] = p.output_intermediate_buffer[ch][:]
		}
		
		status := playback_thread_request_frames(
			&p.playback_thread, output_buf[:spec.channels], spec.samplerate,
			p.config
		)

		if status == .Eof do result = .Finish

		dsp.interlace(output_buf[:spec.channels], data)

		analysis_feed(&p.analysis, output_buf[:spec.channels], spec.samplerate)

		send_event(Buffer_Filled_Event{})

	case .BufferDropped:
		analysis_reset(&p.analysis)
	case .Paused: send_event(Pause_State_Changed_Event{})
	case .Resumed: send_event(Pause_State_Changed_Event{})
	case .TrackFinished:
		log.debug("Track finished, loading next track...")
		playback_thread_close_track(&p.playback_thread)
		play_next_track(immediate = false)
	}

	return
}

init :: proc(cfg: Init_Config) -> shared.Error {
	p := &_player

	if !cfg.no_audio {
		when ODIN_OS == .Windows do audio_init_wasapi() or_return
		else when ODIN_OS == .Linux do audio_init_pulse() or_return
	}
	else {
		audio_init_null()
	}

	shared.event_queue_init(&p.event_queue)
	p.event_queue.wake_proc = cfg.wake_proc

	analysis_init(&p.analysis, context.allocator)

	audio_set_callback(_audio_callback, nil)
	audio_start() or_return

	playback_thread_init(&p.playback_thread, context.allocator)

	p.config = CONFIG_DEFAULTS

	return nil
}

shutdown :: proc() {
	p := &_player
	delete(p.queue)

	playback_thread_destroy(&p.playback_thread)
	audio_shutdown()

	_player = {}
}

wait_for_events :: proc() {
	p := &_player
	shared.event_queue_wait(&p.event_queue)
}

poll_events :: proc() {
	p := &_player

	shared.event_queue_loop_begin(&p.event_queue)
	defer shared.event_queue_loop_end(&p.event_queue)

	_set_queue_pos :: proc(pos: int, immediate: bool = true) -> (ok: bool) {
		p := &_player

		defer if !ok do stop_playback()

		if len(p.queue) == 0 do return
		p.queue_pos = pos

		p.queue_pos = max(p.queue_pos, 0)
		if p.queue_pos >= len(p.queue) {
			if p.repeat_mode == .None do return
			p.queue_pos = len(p.queue) - p.queue_pos
		}

		_play_track(p.queue[p.queue_pos]) or_return

		if immediate do audio_drop_buffer()

		return true
	}

	_play_track :: proc(id: lib.Track_ID) -> bool {
		p := &_player
		track := lib.get_track(id) or_return
		playback_thread_load_track(
			&p.playback_thread, track.url, &p.playing_track_info
		) or_return

		log.info("Now playing:", track.url)

		_set_paused(false)
		p.playing_track_id = id

		return true
	}

	_skip_tracks :: proc(jump: int, immediate: bool) -> bool {
		p := &_player

		tries_left := len(p.queue)

		for !_set_queue_pos(p.queue_pos + jump, immediate) {
			if tries_left <= 0 {
				stop_playback()
				break
			}

			tries_left -= 1
		}

		return true
	}

	_set_paused :: proc(paused: bool) {
		if paused {
			if !audio_is_paused() do audio_pause()
		}
		else {
			if audio_is_paused() do audio_resume()
		}
	}

	for event_union in shared.event_queue_get(&p.event_queue) {
		switch event in event_union {
		case Pause_State_Changed_Event, Buffer_Filled_Event:

		case Set_Paused_Event:
			_set_paused(event.paused)

		case Stop_Event:
			p.playing_track_id = nil
			p.playing_playlist_id = 0
			clear(&p.queue)
			_set_paused(true)
			playback_thread_close_track(&p.playback_thread)

		case Play_Pause_Event:
			if event.pause do audio_pause()
			else do audio_resume()

		case Skip_Track_Event:
			log.debug(event)
			if event.backwards do _skip_tracks(-1, event.immediate)
			else do _skip_tracks(+1, event.immediate)

		case Add_To_Queue_Event:
			_add_to_queue(event.tracks, event.from_playlist, event.assume_unique)

		case Remove_From_Queue_Event:
			_remove_from_queue(event.tracks)

		case Set_Queue_Pos_Event:
			_set_queue_pos(event.pos)

		case Clear_Queue_Event:
			clear(&p.queue)

		case Play_Playlist_Event:
			clear(&p.queue)
			_add_to_queue(event.tracks, event.uid, assume_unique = true)

			if event.initial_track != nil {
				for track, i in p.queue {
					if track == event.initial_track.? {
						_set_queue_pos(i, true)
						break
					}
				}
			}
			else {
				_set_queue_pos(0, true)
			}

		case Play_Track_Event:
			_play_track(event.id)
		}
	}
}

send_event :: proc(event: Event) {
	p := &_player
	q := &p.event_queue
	allocator := q.event_allocator

	#partial switch v in event {
	case Add_To_Queue_Event:
		shared.event_queue_send(q, Add_To_Queue_Event {
			tracks        = slice.clone(v.tracks, allocator),
			assume_unique = v.assume_unique,
			from_playlist = v.from_playlist,
		})
	case Remove_From_Queue_Event:
		shared.event_queue_send(q, Remove_From_Queue_Event {
			tracks = slice.clone(v.tracks, allocator)
		})
	case Play_Playlist_Event:
		shared.event_queue_send(q, Play_Playlist_Event {
			tracks        = slice.clone(v.tracks),
			uid           = v.uid,
			initial_track = v.initial_track,
		})
	case: shared.event_queue_send(q, event)
	}
}

lock :: proc() {sync.lock(&_player.lock)}
unlock :: proc() {sync.unlock(&_player.lock)}

apply_config :: proc(config: Config) {
	lock()
	_player.config = config
	unlock()
}

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

get_volume :: proc() -> f32 {return audio_get_volume()}
set_volume :: proc(v: f32) {audio_set_volume(v)}

set_paused :: proc(paused: bool) {
	send_event(Set_Paused_Event{paused = paused})
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
	log.debugf("Seeking to %02d:%02:%02d", time.clock_from_seconds(auto_cast pos))
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

_add_to_queue :: proc(tracks: []lib.Track_ID, playlist_uid: shared.UID, assume_unique := false) {
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

add_to_queue :: proc(tracks: []lib.Track_ID, playlist_uid: shared.UID, assume_unique := false) {
	send_event(Add_To_Queue_Event {
		tracks        = tracks,
		assume_unique = assume_unique,
		from_playlist = playlist_uid,
	})
}

remove_from_queue :: proc(tracks: []lib.Track_ID) {
	send_event(Remove_From_Queue_Event {
		tracks = tracks,
	})
}

@private
_remove_from_queue :: proc(tracks: []lib.Track_ID) {
	p := &_player
	for remove_id in tracks {
		i := slice.linear_search(p.queue[:], remove_id) or_continue
		ordered_remove(&p.queue, i)
	}

	p.queue_serial += 1
}

set_queue_pos :: proc(pos: int, immediate: bool = true) -> bool {
	send_event(Set_Queue_Pos_Event{pos = pos, immediate = immediate})
	return true
}

set_queue_track :: proc(track: lib.Track_ID) -> bool {
	p := &_player
	index := slice.linear_search(p.queue[:], track) or_return
	return set_queue_pos(index)
}

@private
_play_url :: proc(url: string) -> bool {
	p := &_player
	p.playing_track_id = nil
	p.playing_playlist_id = 0

	return playback_thread_load_track(&p.playback_thread, url, &p.playing_track_info)
}

play_track :: proc(track_id: lib.Track_ID) -> bool {
	send_event(Play_Track_Event{id = track_id})
	return true
}

play_next_track :: proc(immediate: bool = true) -> bool {
	send_event(Skip_Track_Event{backwards = false, immediate = immediate})
	return false
}

play_prev_track :: proc(immediate: bool = true) -> bool {
	send_event(Skip_Track_Event{backwards = true, immediate = immediate})
	return false
}

play_playlist :: proc(tracks: []lib.Track_ID, uid: shared.UID, initial_track: Maybe(lib.Track_ID) = nil) {
	send_event(Play_Playlist_Event {
		tracks        = tracks,
		initial_track = initial_track,
		uid           = uid,
	})
}

stop_playback :: proc() {
	send_event(Stop_Event{})
}

consume_output :: proc(buf: [][]f32) -> Audio_Spec {
	p := &_player
	return analysis_consume(&p.analysis, buf)
}

// Calculate the current ReplayGain output multiplier being applied
calc_effective_replaygain_multiplier :: proc() -> f32 {
	p := &_player
	c := p.config
	info := p.playing_track_info

	if !c.enable_replaygain || p.playing_track_id == nil || info.replay_gain == nil do return 1

	rp := info.replay_gain.?
	gain := c.replaygain_preference == .Track ? rp.track_gain : rp.album_gain
	gain += c.replaygain_pregain

	return dsp.gain_to_amp(gain)
}

