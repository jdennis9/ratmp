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
package playback

import "base:runtime"
import "core:log"
import "core:sync"
import "core:math/rand"
import "core:path/filepath"
import "core:time"

import "player:signal"
import "player:library"
import "player:audio"
import "player:decoder"
import "player:util"
import "player:config"

@private
Library :: library.Library
@private
Track_ID :: library.Track_ID
@private
Playlist_ID :: library.Playlist_ID

Audio_Callback :: #type proc(output: []f32, samplerate: int, channels: int, data: rawptr)

MAX_CHANNELS :: 2

Output_Buffer :: struct {
	timestamp: time.Tick,
	data: [MAX_CHANNELS][]f32,
	samplerate: int,
	channels: int,
}

State :: struct {
	ctx: runtime.Context,
	decoder: decoder.Decoder,
	playing_track: Track_ID,
	lock: sync.Mutex,
	paused: bool,

	queue_position: int,
	queue: [dynamic]Track_ID,
	queued_playlist: Playlist_ID,
	queued_group_id: u32,
	shuffle: bool,

	//stream: audio.Stream_Info,

	devices: []audio.Device_Props,
	current_device: audio.Device_Props,
	default_device_index: int,

	buffer_capture: struct {
		timestamp: time.Tick,
		channels, samplerate: int,
		prev: [MAX_CHANNELS][dynamic]f32,
		next: [MAX_CHANNELS][dynamic]f32,
	},
}

@private
_fill_buffer :: proc(state: ^State, output: []f32, samplerate: int, channels: int) {
	if !sync.atomic_load(&state.paused) {
		status := decoder.fill_buffer(&state.decoder, output, samplerate, channels)
		
		if status == .EOF {
			signal.post(.RequestNext)
		}
		else if status == .NO_FILE {
			for &f in output {f = 0}
		}
	}
	else {
		for &f in output {f = 0}
	}	
}

stream :: proc(state: ^State, buffer: []f32, samplerate, channels: int) {
	context = state.ctx
	frames := len(buffer) / channels
	
	if state.paused || state.decoder.stream == nil {
		for i in 0..<(frames * channels) {
			buffer[i] = 0
		}
		return
	}

	_fill_buffer(state, buffer[:], samplerate, channels)

	// -------------------------------------------------------------------------
	// Update output capture buffer
	// -------------------------------------------------------------------------
	channels := int(channels)
	capture := &state.buffer_capture
	capture.channels = channels
	capture.samplerate = samplerate

	if len(state.buffer_capture.next[0]) > 0 {
		for i in 0..<channels {
			resize(&capture.prev[i], len(capture.next[i]))
			copy(capture.prev[i][:], capture.next[i][:])
		}

		// This probably needs to change for audio backends other than WASAPI
		_deinterlace(buffer, channels, &state.buffer_capture.next)
		buffer_seconds := f32(frames) / f32(samplerate)
		capture.timestamp = time.tick_now()
		capture.timestamp._nsec -= auto_cast(buffer_seconds * 1e9)/2
	}
	else {
		_deinterlace(buffer, channels, &state.buffer_capture.next)
		state.buffer_capture.timestamp = time.tick_now()
	}
}

/*@private
_signal_handler :: proc(sig: signal.Signal) {
	if sig == .RequestNext {play_next_track()}
	else if sig == .RequestPrev {play_prev_track()}
	else if sig == .RequestPause {set_paused(true)}
	else if sig == .RequestPlay {set_paused(false)}
	else if sig == .ApplyPrefs {
		this.shuffle = prefs.get_property("playback_shuffle").(bool) or_else false
	}
}*/

init :: proc() -> (state: State, ok: bool) {
	state.ctx = context
	state.paused = true
	//signal.install_handler(_signal_handler)
	audio.init() or_return
	/*refresh_audio_devices(&state) or_return

	if prefs.prefs.strings[.PlaybackDevice][0] != 0 {
		want_device_id := cstring(&prefs.prefs.strings[.PlaybackDevice][0])

		for &device, device_index in state.devices {
			if cstring(&device.id[0]) == want_device_id {
				set_audio_device_index(&state, device_index) or_return
				break
			}
		}
	}
	else {
		set_audio_device_index(&state, state.default_device_index) or_return
	}*/

	ok = true
	return
}

destroy :: proc(state: ^State) {
	delete(state.queue)
	for ch in 0..<MAX_CHANNELS {
		delete(state.buffer_capture.prev[ch])
		delete(state.buffer_capture.next[ch])
	}
	decoder.close(&state.decoder)
}

@private
_play_file :: proc(state: ^State, path: string) -> bool {
	sync.lock(&state.lock)
	defer sync.unlock(&state.lock)
	log.debug("Playing file", filepath.base(path))

	// Clear output buffer
	for ch in 0..<MAX_CHANNELS {
		delete(state.buffer_capture.next[ch])
		state.buffer_capture.next[ch] = nil
		delete(state.buffer_capture.prev[ch])
		state.buffer_capture.prev[ch] = nil
	}

	return decoder.open(&state.decoder, path)
}

is_paused :: proc(state: State) -> bool {
	return state.paused || (state.playing_track == 0)
}

set_paused :: proc(state: ^State, paused: bool) {
	if !paused && state.playing_track == 0 {
		sync.atomic_store(&state.paused, true)
		return
	}
	sync.atomic_store(&state.paused, paused)
	signal.post(.PlaybackStateChanged)
	audio.interrupt()
}

toggle :: proc(state: ^State) {
	paused := sync.atomic_load(&state.paused)
	if paused {set_paused(state, false)}
	else {set_paused(state, true)}
}

stop :: proc(state: ^State) {
	sync.lock(&state.lock)
	decoder.close(&state.decoder)
	sync.unlock(&state.lock)
	
	clear(&state.queue)
	state.playing_track = 0
	
	signal.post(.PlaybackStopped)
	audio.interrupt()
}

toggle_shuffle :: proc(state: ^State) {
	state.shuffle = !state.shuffle
	config.set_property("playback_shuffle", state.shuffle)
}

play_track :: proc(state: ^State, lib: library.Library, track: library.Track_ID) -> bool {
	buf: [512]u8
	path := library.get_track_path(lib, track, buf[:])
	if (_play_file(state, path)) {
		state.playing_track = track
		set_paused(state, false)
		signal.post(.TrackChanged)
		return true
	}

	state.playing_track = 0

	return false
}

// =============================================================================
// Output reading
// =============================================================================

@private
_deinterlace :: proc(input: []f32, channels: int, out: ^[MAX_CHANNELS][dynamic]f32) {
	for ch in 0..<channels {
		resize(&out[ch], len(input)/channels)
	}

	sample_count := len(input)
	sample: int
	frame: int

	for sample < sample_count {
		for ch in 0..<channels {
			out[ch][frame] = input[sample + ch]
		}

		sample += channels
		frame += 1
	}
}

update_output_copy_buffer :: proc(state: State, buffer: ^Output_Buffer) -> bool {
	capture := state.buffer_capture

	if state.paused {
		for c in 0..<MAX_CHANNELS {
			delete(buffer.data[c])
			buffer.data[c] = nil
		}

		return false
	}

	// No need to update
	if buffer.data[0] != nil && buffer.timestamp == state.buffer_capture.timestamp {
		return false
	}

	buffer.channels = auto_cast state.buffer_capture.channels
	buffer.samplerate = auto_cast state.buffer_capture.samplerate
	buffer.timestamp = state.buffer_capture.timestamp

	for i in 0..<buffer.channels {
		delete(buffer.data[i])
		buffer.data[i] = make([]f32, len(capture.prev[i]) + len(capture.next[i]))
		copy(buffer.data[i][:], capture.prev[i][:])
		copy(buffer.data[i][len(capture.prev[i]):], capture.next[i][:])
	}

	return true
}

get_output_buffer_view :: proc(buffer: ^Output_Buffer, frame_count: int) -> (view: Output_Buffer) {
	if len(buffer.data[0]) == 0 {return}

	view.channels = buffer.channels
	view.samplerate = buffer.samplerate

	delta := cast(f32) time.duration_seconds(time.tick_diff(buffer.timestamp, time.tick_now()))
	first_frame := int(delta * f32(buffer.samplerate))
	first_frame = max(first_frame, 0)
	frame_count := min(frame_count, len(buffer.data[0]) - first_frame)
	if frame_count < 0 {return}

	for ch in 0..<view.channels {
		view.data[ch] = buffer.data[ch][first_frame:][:frame_count]
	}

	return
}

// =============================================================================
// Seeking
// =============================================================================

seek :: proc(state: ^State, second: int) {
	sync.lock(&state.lock)
	decoder.seek(&state.decoder, second)
	sync.unlock(&state.lock)
	audio.interrupt()
}

get_second :: proc(state: State) -> int {
	return decoder.get_second(state.decoder)
}

get_duration :: proc(state: State) -> int {
	return decoder.get_duration(state.decoder)
}

// =============================================================================
// Queue management
// =============================================================================

play_playlist :: proc(state: ^State, lib: Library, playlist: library.Playlist, first_track: library.Track_ID = 0, use_filter := false) {
	state.queued_playlist = playlist.id
	state.queued_group_id = playlist.group_id
	clear(&state.queue)

	for track in playlist.tracks {
		append(&state.queue, track)
	}

	if state.shuffle {
		rand.shuffle(state.queue[:])
	}

	state.queue_position = 0

	if first_track != 0 {
		for track, index in state.queue {
			if track == first_track {
				state.queue_position = index
				break
			}
		}
	}

	play_track_at_position(state, lib, state.queue_position)
}

append_to_queue :: proc(state: ^State, tracks: []library.Track_ID) {
	state.queued_playlist = 0
	state.queued_group_id = 0
	for track in tracks {
		append(&state.queue, track)
	}
}

play_track_at_position :: proc(state: ^State, lib: Library, in_pos: int) {
	pos := in_pos

	if len(state.queue) == 0 {
		return
	}

	if pos >= len(state.queue) || pos < 0 {
		pos = 0
	}

	if !play_track(state, lib, state.queue[pos]) {
		signal.post(.RequestNext)
	}
	state.queue_position = pos
}

play_track_array :: proc(state: ^State, lib: Library, tracks: []Track_ID) {
	state.queued_playlist = 0
	clear(&state.queue)
	for track in tracks {
		append(&state.queue, track)
	}

	if state.shuffle {
		rand.shuffle(state.queue[:])
	}

	play_track_at_position(state, lib, 0)
}

play_next_track :: proc(state: ^State, lib: Library) {
	play_track_at_position(state, lib, state.queue_position + 1)
}

play_prev_track :: proc(state: ^State, lib: Library) {
	play_track_at_position(state, lib, state.queue_position - 1)
}

sort_queue :: proc(state: State, lib: library.Library, spec: library.Track_Sort_Spec) {
	library.sort_tracks(lib, state.queue[:], spec)
}

// =============================================================================
// Volume
// =============================================================================

set_volume :: proc(vol: f32) {
	audio.set_volume(vol)
}

get_volume :: proc() -> f32 {
	return audio.get_volume()
}

// =============================================================================
// Audio
// =============================================================================
/*refresh_audio_devices :: proc(state: ^State) -> bool {
	delete(state.devices)
	state.devices = audio.enumerate_devices() or_return
	default_id := audio.get_default_device_id() or_return

	for &device, index in state.devices {
		if cstring(&device.id[0]) == cstring(&default_id[0]) {
			state.default_device_index = index
		}
	}

	return true
}

get_audio_devices :: proc(state: State) -> []audio.Device_Props {
	return state.devices
}

set_audio_device_index :: proc(state: ^State, index: int) -> bool {
	audio.stop()
	state.stream = audio.start(&state.devices[index].id, _stream_callback, nil) or_return
	state.current_device = state.devices[index]
	return true
}*/