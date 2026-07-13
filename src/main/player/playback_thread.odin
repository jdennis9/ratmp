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
#+private
package player

import "src:main/decoder"
import "src:main/shared"
import "src:dsp"
import "core:mem"
import "core:math"
import "core:log"
import "core:sync"
import "core:thread"

Ring_Buffer :: shared.Ring_Buffer

// =============================================================================
// Procedures to create and interact with an asynchronous playback stream.
// Exists to keep decoding and post-processing away from the main audio thread,
// and do it before the audio is needed.
// =============================================================================

Playback_Thread_Status :: enum {
	MoreInput,
	NoInput,
	Eof,
}

Playback_Thread :: struct {
	runner:                 ^thread.Thread,
	allocator:              mem.Allocator,
	processing_allocator:   mem.Allocator,
	processing_arena:       mem.Dynamic_Arena,
	ring_buffers:           [AUDIO_MAX_CHANNELS]Ring_Buffer(f32),
	ring_buffer_channels:   int,
	ring_buffer_samplerate: int,
	dec:                    decoder.Decoder,
	decode_status:          decoder.Status,
	request_fill_signal:    sync.Auto_Reset_Event,
	buffer_filled_signal:   sync.Auto_Reset_Event,
	lock:                   sync.Mutex,

	// Index of last frame consumed in the samplerate of the input
	consumed_frame_index: int,

	// Set by playback_thread_request_frames
	input: struct {
		frames_requested: int,
		samplerate:       int,
		channels:         int,
		config:           Config,
	},

	audio_buffer: [AUDIO_MAX_CHANNELS][dynamic]f32,
}

@(private="file")
_pad_ring_buffer_size :: proc(x: int) -> int {
	pow := 1
	for pow < x do pow *= 2
	return max(pow, 32<<10)
}

@(private="file")
_reset_ring_buffers :: proc(at: ^Playback_Thread) {
	for &rb in at.ring_buffers[:at.ring_buffer_channels] do shared.rb_reset(&rb)
}

@(private="file")
_post_process :: proc(at: ^Playback_Thread, audio: [][]f32, samplerate: f32) {
	config := at.input.config

	// ReplayGain
	if at.dec.replay_gain != nil && config.enable_replaygain {
		rp := at.dec.replay_gain.?
		gain := config.replaygain_preference == .Track ? rp.track_gain : rp.album_gain
		gain += config.replaygain_pregain
		v := dsp.gain_to_amp(gain)

		for ch in audio {
			for &f in ch {
				f *= v
			}
		}
	}

	// Safety clipping to prevent super loud pops that can sometimes happen
	// at the start of playback
	for ch in audio {
		for &f in ch {
			if abs(f) > 10 do f = 0
		}
	}
}

@(private="file")
_thread_proc :: proc(thr: ^thread.Thread) {
	at := cast(^Playback_Thread) thr.data

	for {
		frames_copied: int
		frames_required: int
		deinterlaced: [AUDIO_MAX_CHANNELS][]f32

		sync.auto_reset_event_wait(&at.request_fill_signal)
		defer sync.auto_reset_event_signal(&at.buffer_filled_signal)

		sync.lock(&at.lock)
		defer sync.unlock(&at.lock)

		if at.input.channels == 0 || at.input.samplerate == 0 do continue
		if !decoder.is_open(at.dec) do continue
		
		if at.input.frames_requested > len(at.ring_buffers[0].data) {
			ring_buffer_size := _pad_ring_buffer_size(at.input.frames_requested*2)
			log.debug("Resizing ring buffer to", ring_buffer_size)

			for &rb in at.ring_buffers[:at.input.channels] {
				if rb.data == nil {
					shared.rb_init(&rb, ring_buffer_size, at.allocator)
				}
				else {
					shared.rb_reset(&rb)
					shared.rb_resize(&rb, ring_buffer_size)
				}
			}
		}	

		if at.ring_buffer_channels != at.input.channels || at.ring_buffer_samplerate != at.input.samplerate {
			at.ring_buffer_channels = at.input.channels
			at.ring_buffer_samplerate = at.input.samplerate
			_reset_ring_buffers(at)
		}

		frames_required = shared.rb_space(at.ring_buffers[0])

		if frames_required <= 0 do continue
		
		for ch in 0..<at.input.channels {
			resize(&at.audio_buffer[ch], frames_required)
			deinterlaced[ch] = at.audio_buffer[ch][:]
		}

		at.decode_status = decoder.decode(&at.dec, deinterlaced[:at.input.channels], at.input.samplerate)

		// Post-processing
		/*if at.post_process_hook.process != nil do at.post_process_hook.process(
			at.post_process_hook.data, deinterlaced[:at.channels], at.samplerate
		)*/
		_post_process(at, deinterlaced[:at.input.channels], f32(at.input.samplerate))

		for d, ch in deinterlaced[:at.input.channels] {
			frames_copied = shared.rb_produce(&at.ring_buffers[ch], d)
		}
	}
}

playback_thread_init :: proc(at: ^Playback_Thread, allocator: mem.Allocator) {
	mem.dynamic_arena_init(&at.processing_arena)

	at.allocator            = allocator
	at.processing_allocator = mem.dynamic_arena_allocator(&at.processing_arena)
	at.runner               = thread.create(_thread_proc)
	at.runner.data          = at
	at.runner.init_context  = context
	thread.start(at.runner)
}

playback_thread_destroy :: proc(at: ^Playback_Thread) {
}

playback_thread_request_frames :: proc(
	at: ^Playback_Thread, output: [][]f32, samplerate: int, config: Config,
) -> Playback_Thread_Status {
	channels := len(output)
	frames_read := 0
	frames_wanted := len(output[0])
	iter_count := 0
	
	at.input.config = config

	for frames_read < frames_wanted {
		{
			sync.guard(&at.lock)
			
			if !decoder.is_open(at.dec) do return .NoInput
			
			// Help the thread proc to know what to size the ring buffers
			at.input.frames_requested = frames_wanted
			
			if at.ring_buffer_channels == len(output) && at.ring_buffer_samplerate == samplerate {
				frames_copied: int
				
				for &rb, ch in at.ring_buffers[:channels] {
					o := output[ch][frames_read:]
					frames_copied = shared.rb_consume(&rb, o, nil)
				}
				
				frames_read += frames_copied
				iter_count += 1
			}
			else {
				at.input.channels = len(output)
				at.input.samplerate = samplerate
			}
		}
		
		if frames_read < frames_wanted {
			sync.auto_reset_event_signal(&at.request_fill_signal)
			sync.auto_reset_event_wait(&at.buffer_filled_signal)
		}		
	}
	
	if iter_count > 1 do log.warn(iter_count, "iterations! Ring buffer too small!")
	
	at.consumed_frame_index += cast(int) math.ceil(
		f32(frames_wanted) * (f32(at.dec.samplerate) / f32(samplerate))
	)

	// Signal to fill the buffer before the next call to this proc
	sync.auto_reset_event_signal(&at.request_fill_signal)

	if at.consumed_frame_index < at.dec.frame_count do return .MoreInput
	else do return .Eof
}

playback_thread_load_track :: proc(at: ^Playback_Thread, url: string, file_info: ^decoder.Info) -> bool {
	log.debug("Playing track", url)

	sync.lock(&at.lock)
	defer sync.unlock(&at.lock)

	_reset_ring_buffers(at)
	at.consumed_frame_index = 0
	decoder.close(&at.dec)
	decoder.open(&at.dec, url, file_info) or_return

	return true
}

playback_thread_close_track :: proc(at: ^Playback_Thread) {
	sync.lock(&at.lock)
	defer sync.unlock(&at.lock)
	decoder.close(&at.dec)
}

playback_thread_seek :: proc(at: ^Playback_Thread, second: int) {
	sync.lock(&at.lock)
	defer sync.unlock(&at.lock)
	_reset_ring_buffers(at)
	decoder.seek(&at.dec, second)
	at.consumed_frame_index = at.dec.frame_index
}

playback_thread_get_track_position :: proc(at: ^Playback_Thread) -> int {
	sync.lock(&at.lock)
	defer sync.unlock(&at.lock)
	if !decoder.is_open(at.dec) do return 0
	return at.consumed_frame_index / at.dec.samplerate
}

playback_thread_has_track :: proc(at: Playback_Thread) -> bool {
	return decoder.is_open(at.dec)
}
