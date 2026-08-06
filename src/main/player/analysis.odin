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

import "core:log"
import "core:time"
import "core:sync"
import "core:math/linalg"
import "core:mem"
import resampler "src:bindings/samplerate"
import "src:main/shared"

ANALYSIS_BUFFER_SIZE :: 64<<10

// Use a constant sample rate for analysis for
// consistent behaviour of visualizers
ANALYSIS_SAMPLE_RATE :: 48000

Analysis_Buffer :: struct {
	channels:             int,
	rs:                   [AUDIO_MAX_CHANNELS]resampler.State,
	rings:                [AUDIO_MAX_CHANNELS]shared.Ring_Buffer(f32),
	allocator:            mem.Allocator,
	resample_buf:         [dynamic]f32,
	lock:                 sync.Mutex,
	last_consume:         time.Tick,
	last_chunk_consumed:  bool,
	empty:                bool,
}

analysis_init :: proc(buf: ^Analysis_Buffer, allocator: mem.Allocator) {
	buf.allocator = allocator
	buf.resample_buf = make([dynamic]f32, allocator)
}

analysis_feed :: proc(buf: ^Analysis_Buffer, input: [][]f32, samplerate: int) {
	channels := len(input)
	buf.channels = channels

	sync.guard(&buf.lock)
	
	defer buf.empty = false

	for ch in 0..<channels {
		if buf.rings[ch].data == nil {
			shared.rb_init(&buf.rings[ch], ANALYSIS_BUFFER_SIZE, buf.allocator)
		}

		if buf.rs[ch] == nil {
			buf.rs[ch] = resampler.new(.SINC_FASTEST, 1, nil)
		}
	}

	if !buf.last_chunk_consumed {
		log.warn("Last chunk not consumed, skipping samples")
		sync.unlock(&buf.lock)
		analysis_consume(buf, nil)
		sync.lock(&buf.lock)
	}

	buf.last_chunk_consumed = false

	if samplerate == ANALYSIS_SAMPLE_RATE {
		for samples, ch in input {
			shared.rb_produce(&buf.rings[ch], samples)
		}
	}
	else {
		ratio := ANALYSIS_SAMPLE_RATE / f32(samplerate)
		resize(&buf.resample_buf, int(linalg.ceil(f32(len(input[0])) * ratio)))

		for samples, ch in input {
			data := resampler.Data {
				data_in       = raw_data(samples),
				data_out      = raw_data(buf.resample_buf),
				input_frames  = auto_cast len(samples),
				output_frames = auto_cast len(buf.resample_buf),
				src_ratio     = f64(ratio),
			}

			resampler.process(buf.rs[ch], &data)
			shared.rb_produce(&buf.rings[ch], buf.resample_buf[:])
		}
	}
}

analysis_consume :: proc(buf: ^Analysis_Buffer, output: [][]f32) -> Audio_Spec {
	sync.guard(&buf.lock)

	if buf.empty do return {}

	buf.last_chunk_consumed = true

	now := time.tick_now()
	span := cast(f32) time.duration_seconds(time.tick_diff(buf.last_consume, now))
	consume_count := int(linalg.floor(span * ANALYSIS_SAMPLE_RATE))

	if output != nil {
		for ch in 0..<buf.channels {
			shared.rb_consume(&buf.rings[ch], output[ch], consume_count)
		}
	}
	else {
		for ch in 0..<buf.channels {
			shared.rb_consume(&buf.rings[ch], nil, consume_count)
		}
	}

	buf.last_consume = now

	return {channels = buf.channels, samplerate = ANALYSIS_SAMPLE_RATE}
}

analysis_reset :: proc(buf: ^Analysis_Buffer) {
	buf.empty = true

	for &ring in buf.rings {
		shared.rb_reset(&ring)
	}

	for rs in buf.rs {
		if rs != nil do resampler.reset(rs)
	}
}
