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
package server

// =============================================================================
// Procedures to create and interact with an asynchronous playback stream.
// Exists to keep decoding and post-processing away from the main audio thread,
// and do it before the audio is needed.
// =============================================================================

import "core:math"
import "src:audio"
import "core:log"
import "core:sync"
import "src:decoder"
import "src:util"
import "core:thread"

Playback_Thread_Status :: enum {
	MoreInput,
	NoInput,
	Eof,
}

Playback_Thread :: struct {
	runner: ^thread.Thread,
	ring_buffers: [MAX_OUTPUT_CHANNELS]util.Ring_Buffer(f32),
	ring_buffer_channels: int,
	ring_buffer_samplerate: int,
	dec: decoder.Decoder,
	decode_status: decoder.Decode_Status,
	post_process_hook: Post_Process_Hook,
	request_fill_signal: sync.Auto_Reset_Event,
	buffer_filled_signal: sync.Auto_Reset_Event,
	lock: sync.Mutex,

	// Index of last frame consumed in the samplerate of the input
	consumed_frame_index: int,

	// Set by playback_thread_request_frames
	frames_requested: int,
	samplerate, channels: int,
}

Playback_Thread_Params :: struct {
	post_process_hook: Post_Process_Hook,
}

@(private="file")
_next_power_of_2 :: proc(x: int) -> int {
	pow := 1
	for pow < x do pow *= 2
	return pow
}

@(private="file")
_reset_ring_buffers :: proc(at: ^Playback_Thread) {
	for &rb in at.ring_buffers[:at.ring_buffer_channels] do util.rb_reset(&rb)
}

@(private="file")
_thread_proc :: proc(thr: ^thread.Thread) {
	at := cast(^Playback_Thread) thr.data

	for {
		frames_copied: int
		frames_required: int
		buffer: []f32
		deinterlaced: [MAX_OUTPUT_CHANNELS][]f32

		sync.auto_reset_event_wait(&at.request_fill_signal)
		defer sync.auto_reset_event_signal(&at.buffer_filled_signal)

		sync.lock(&at.lock)
		defer sync.unlock(&at.lock)

		if at.channels == 0 || at.samplerate == 0 do continue
		if !decoder.is_open(at.dec) do continue
		
		if at.frames_requested > len(at.ring_buffers[0].data) {
			ring_buffer_size := _next_power_of_2(at.frames_requested)
			log.debug("Resizing ring buffer to", ring_buffer_size)

			for &rb in at.ring_buffers[:at.channels] {
				util.rb_reset(&rb)
				util.rb_resize(&rb, ring_buffer_size)
			}
		}	

		if at.ring_buffer_channels != at.channels || at.ring_buffer_samplerate != at.samplerate {
			at.ring_buffer_channels = at.channels
			at.ring_buffer_samplerate = at.samplerate
			_reset_ring_buffers(at)
		}

		frames_required = util.rb_space(at.ring_buffers[0])

		if frames_required <= 0 do continue

		buffer = make([]f32, at.channels * frames_required)
		defer delete(buffer)
		
		for ch in 0..<at.channels do deinterlaced[ch] = make([]f32, frames_required)
		defer for d in deinterlaced do delete(d)

		at.decode_status = decoder.fill_buffer(&at.dec, buffer, at.channels, at.samplerate)

		audio.deinterlace(buffer, deinterlaced[:at.channels])

		// Post-processing
		if at.post_process_hook.process != nil do at.post_process_hook.process(
			at.post_process_hook.data, deinterlaced[:at.channels], at.samplerate
		)

		for d, ch in deinterlaced[:at.channels] {
			frames_copied = util.rb_produce(&at.ring_buffers[ch], d)
		}
	}
}

playback_thread_init :: proc(at: ^Playback_Thread, params: Playback_Thread_Params) {
	at.post_process_hook = params.post_process_hook
	at.runner = thread.create(_thread_proc)
	at.runner.data = at
	at.runner.init_context = context
	thread.start(at.runner)
}

playback_thread_request_frames :: proc(
	at: ^Playback_Thread, output: [][]f32, samplerate: int
) -> Playback_Thread_Status {
	channels := len(output)
	frames_read := 0
	frames_wanted := len(output[0])
	iter_count := 0

	for frames_read < frames_wanted {
		iter_count += 1

		{
			sync.lock(&at.lock)
			defer sync.unlock(&at.lock)

			if !decoder.is_open(at.dec) do return .NoInput

			// Help the thread proc to know what to size the ring buffers
			at.frames_requested = frames_wanted

			if at.ring_buffer_channels == len(output) && at.ring_buffer_samplerate == samplerate {
				frames_copied: int
				
				for &rb, ch in at.ring_buffers[:channels] {
					o := output[ch][frames_read:]
					frames_copied = util.rb_consume(&rb, o, nil)
				}
				
				frames_read += frames_copied
			}
			else {
				at.channels = len(output)
				at.samplerate = samplerate
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

playback_thread_load_track :: proc(at: ^Playback_Thread, path: string, file_info: ^decoder.File_Info) -> bool {
	sync.lock(&at.lock)
	defer sync.unlock(&at.lock)
	_reset_ring_buffers(at)
	at.consumed_frame_index = 0
	decoder.close(&at.dec)
	decoder.open(&at.dec, path, file_info) or_return

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
