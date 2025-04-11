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
package playback;

import "base:runtime";
import "core:log";
import "core:sync";
import "core:math/rand";
import "core:path/filepath";
import "core:time";

import "../signal";
import lib "../library";
import "../audio";
import "../decoder";
import "../util";

Audio_Callback :: #type proc(output: []f32, samplerate: int, channels: int, data: rawptr);

MAX_CHANNELS :: 2

Output_Buffer :: struct {
	timestamp: time.Tick,
	data: [MAX_CHANNELS][]f32,
	samplerate: int,
	channels: int,
};

@private
this: struct {
	ctx: runtime.Context,
	decoder: decoder.Decoder,
	playing_track: lib.Track,
	lock: sync.Mutex,
	paused: bool,

	queue_position: int,
	queue: lib.Playlist,
	queued_playlist: lib.Playlist_ID,
	queued_group_id: u32,
	shuffle: bool,

	stream: audio.Stream_Info,

	buffer_capture: struct {
		timestamp: time.Tick,
		prev: [MAX_CHANNELS][dynamic]f32,
		next: [MAX_CHANNELS][dynamic]f32,
	},
};

@private
_fill_buffer :: proc(output: []f32, samplerate: int, channels: int) {
	if !sync.atomic_load(&this.paused) {
		status := decoder.fill_buffer(&this.decoder, output, samplerate, channels);
		
		if status == .EOF {
			signal.post(.RequestNext);
		}
		else if status == .NO_FILE {
			for &f in output {f = 0}
		}
	}
	else {
		for &f in output {f = 0}
	}	
}

@private
_stream_callback :: proc(buffer: []f32, _: rawptr) {
	sync.lock(&this.lock);
	defer sync.unlock(&this.lock);

	context = this.ctx;
	frames := i32(len(buffer)) / this.stream.channels;
	
	if this.paused || this.decoder.stream == nil {
		for i in 0..<(frames * this.stream.channels) {
			buffer[i] = 0;
		}
		return;
	}

	_fill_buffer(
		buffer[:], 
		cast(int) this.stream.sample_rate, cast(int) this.stream.channels
	);

	// -------------------------------------------------------------------------
	// Update output capture buffer
	// -------------------------------------------------------------------------
	channels := int(this.stream.channels);
	capture := &this.buffer_capture;

	if len(this.buffer_capture.next[0]) > 0 {
		for i in 0..<channels {
			resize(&capture.prev[i], len(capture.next[i]));
			copy(capture.prev[i][:], capture.next[i][:]);
		}

		// This probably needs to change for audio backends other than WASAPI
		_deinterlace(buffer, channels, &this.buffer_capture.next);
		buffer_seconds := f32(frames) / f32(this.stream.sample_rate);
		capture.timestamp = time.tick_now();
		capture.timestamp._nsec -= auto_cast(buffer_seconds * 1e9)/2;
	}
	else {
		_deinterlace(buffer, channels, &this.buffer_capture.next);
		this.buffer_capture.timestamp = time.tick_now();
	}
}

@private
_signal_handler :: proc(sig: signal.Signal) {
	if sig == .RequestNext {play_next_track()}
	else if sig == .RequestPrev {play_prev_track()}
	else if sig == .RequestPause {set_paused(true)}
	else if sig == .RequestPlay {set_paused(false)}
}

init :: proc() -> bool {
	this.ctx = context;
	this.paused = true;
	this.queue.name = "Queue";
	signal.install_handler(_signal_handler);
	audio.init() or_return;
	//audio.run(_stream_callback, nil, &this.stream);
	this.stream = audio.start(audio.get_default_device_index(), _stream_callback, nil);
	//return cast(bool) audio.run(_stream_callback, nil, &this.stream);
	return true;
}

shutdown :: proc() {
	//audio.kill();
	audio.stop();
	audio.shutdown();
}

@private
_play_file :: proc(path: string) -> bool {
	sync.lock(&this.lock);
	defer sync.unlock(&this.lock);
	log.debug("Playing file", filepath.base(path));

	// Clear output buffer
	for ch in 0..<this.stream.channels {
		delete(this.buffer_capture.next[ch]);
		this.buffer_capture.next[ch] = nil;
		delete(this.buffer_capture.prev[ch]);
		this.buffer_capture.prev[ch] = nil;
	}

	return decoder.open(&this.decoder, path);
}

get_playing_track :: proc() -> lib.Track {
	return this.playing_track;
}

is_paused :: proc() -> bool {
	return this.paused || (this.playing_track == 0);
}

set_paused :: proc(paused: bool) {
	if !paused && this.playing_track == 0 {
		sync.atomic_store(&this.paused, true);
		return;
	}
	sync.atomic_store(&this.paused, paused);
	signal.post(.PlaybackStateChanged);
	audio.interrupt();
}

toggle :: proc() {
	paused := sync.atomic_load(&this.paused);
	if paused {set_paused(false)}
	else {set_paused(true)}
}

stop :: proc() {
	sync.lock(&this.lock);
	decoder.close(&this.decoder);
	sync.unlock(&this.lock);
	
	clear(&this.queue.tracks);
	this.playing_track = 0;
	
	signal.post(.PlaybackStopped);
	audio.interrupt();
}

toggle_shuffle :: proc() {this.shuffle = !this.shuffle;}
is_shuffle_enabled :: proc() -> bool {return this.shuffle;}

play_track :: proc(track: lib.Track) -> bool {
	buf: [512]u8;
	path := lib.get_track_path(track, buf[:]);
	if (_play_file(path)) {
		this.playing_track = track;
		set_paused(false);
		signal.post(.TrackChanged);
		return true;
	}

	this.playing_track = 0;

	return false;
}

// =============================================================================
// Output reading
// =============================================================================

@private
_deinterlace :: proc(input: []f32, channels: int, out: ^[MAX_CHANNELS][dynamic]f32) {
	for ch in 0..<channels {
		resize(&out[ch], len(input)/channels);
	}

	sample_count := len(input);
	sample: int;
	frame: int;

	for sample < sample_count {
		for ch in 0..<channels {
			out[ch][frame] = input[sample + ch];
		}

		sample += channels;
		frame += 1;
	}
}

update_output_copy_buffer :: proc(buffer: ^Output_Buffer) -> bool {
	sync.lock(&this.lock);
	defer sync.unlock(&this.lock);

	capture := &this.buffer_capture;

	if this.paused {
		for c in 0..<MAX_CHANNELS {
			delete(buffer.data[c]);
			buffer.data[c] = nil;
		}

		return false;
	}

	// No need to update
	if buffer.data[0] != nil && buffer.timestamp == this.buffer_capture.timestamp {
		return false;
	}

	buffer.channels = auto_cast this.stream.channels;
	buffer.samplerate = auto_cast this.stream.sample_rate;
	buffer.timestamp = this.buffer_capture.timestamp;

	for i in 0..<buffer.channels {
		delete(buffer.data[i]);
		buffer.data[i] = make([]f32, len(capture.prev[i]) + len(capture.next[i]));
		copy(buffer.data[i][:], capture.prev[i][:]);
		copy(buffer.data[i][len(capture.prev[i]):], capture.next[i][:]);
	}

	return true;
}

get_output_buffer_view :: proc(buffer: ^Output_Buffer, frame_count: int) -> (view: Output_Buffer) {
	if len(buffer.data[0]) == 0 {return}

	view.channels = buffer.channels;
	view.samplerate = buffer.samplerate;

	delta := cast(f32) time.duration_seconds(time.tick_diff(buffer.timestamp, time.tick_now()));
	first_frame := int(delta * f32(buffer.samplerate));
	first_frame = max(first_frame, 0);
	frame_count := min(frame_count, len(buffer.data[0]) - first_frame);
	if frame_count < 0 {return}

	for ch in 0..<view.channels {
		view.data[ch] = buffer.data[ch][first_frame:][:frame_count];
	}

	return;
}

// =============================================================================
// Seeking
// =============================================================================

seek :: proc(second: int) {
	sync.lock(&this.lock);
	decoder.seek(&this.decoder, second);
	sync.unlock(&this.lock);
	audio.interrupt();
}

get_second :: proc() -> int {
	sync.lock(&this.lock);
	defer sync.unlock(&this.lock);
	return decoder.get_second(&this.decoder);
}

get_duration :: proc() -> int {
	sync.lock(&this.lock);
	defer sync.unlock(&this.lock);
	return decoder.get_duration(&this.decoder);
}

// =============================================================================
// Queue management
// =============================================================================

get_queue :: proc() -> ^lib.Playlist {
	return &this.queue;
}

get_queued_playlist :: proc() -> lib.Playlist_ID {
	return this.queued_playlist;
}

get_queued_group_id :: proc() -> u32 {
	return this.queued_group_id;
}

play_playlist :: proc(playlist: lib.Playlist, first_track: lib.Track = 0, use_filter := false) {
	this.queued_playlist = playlist.id;
	this.queued_group_id = playlist.group_id;
	lib.playlist_clear(&this.queue);

	if use_filter && playlist.filter_hash != 0 {
		for index in playlist.filter_tracks {
			lib.playlist_add_tracks(&this.queue, {playlist.tracks[index]}, false);
		}	
	}
	else {
		lib.playlist_add_tracks(&this.queue, playlist.tracks[:]);
	}

	if this.shuffle {
		rand.shuffle(this.queue.tracks[:]);
	}

	this.queue_position = 0;

	if first_track != 0 {
		for track, index in this.queue.tracks {
			if track == first_track {
				this.queue_position = index;
				break;
			}
		}
	}

	play_track_at_position(this.queue_position);
}

append_to_queue :: proc(tracks: []lib.Track) {
	this.queued_playlist = 0;
	this.queued_group_id = 0;
	lib.playlist_add_tracks(&this.queue, tracks);
}

play_track_at_position :: proc(in_pos: int) {
	pos := in_pos;

	if len(this.queue.tracks) == 0 {
		return;
	}

	if pos >= len(this.queue.tracks) || pos < 0 {
		pos = 0;
	}

	if !play_track(this.queue.tracks[pos]) {
		signal.post(.RequestNext);
	}
	this.queue_position = pos;
}

play_track_array :: proc(tracks: []lib.Track) {
	this.queued_playlist = 0;
	lib.playlist_clear(&this.queue);
	lib.playlist_add_tracks(&this.queue, tracks);

	if this.shuffle {
		rand.shuffle(this.queue.tracks[:]);
	}

	play_track_at_position(0);
}

play_next_track :: proc() {
	play_track_at_position(this.queue_position + 1);
}

play_prev_track :: proc() {
	play_track_at_position(this.queue_position - 1);
}

// =============================================================================
// Volume
// =============================================================================

set_volume :: proc(vol: f32) {
	audio.set_volume(vol);
}

get_volume :: proc() -> f32 {
	return audio.get_volume();
}
