package main

import "core:math/linalg"
import "core:mem"
import resampler "src:bindings/samplerate"


ANALYSIS_RING_BUFFER_SIZE :: 64<<10

// Use a constant sample rate for analysis for
// consistent behaviour of visualizers
ANALYSIS_SAMPLE_RATE :: 48000

Analysis_Buffer :: struct {
	rings:        [AUDIO_MAX_CHANNELS]Ring_Buffer(f32),
	channels:     int,
	rs:           [AUDIO_MAX_CHANNELS]resampler.State,
	allocator:    mem.Allocator,
	resample_buf: [dynamic]f32,
}

analysis_init :: proc(buf: ^Analysis_Buffer, allocator: mem.Allocator) {
	buf.allocator = allocator
	buf.resample_buf = make([dynamic]f32, allocator)
}

analysis_feed :: proc(buf: ^Analysis_Buffer, input: [][]f32, samplerate: int) {
	channels := len(input)
	buf.channels = channels

	for ch in 0..<channels {
		if buf.rings[ch].data == nil {
			rb_init(&buf.rings[ch], ANALYSIS_RING_BUFFER_SIZE, buf.allocator)
		}
		
		if buf.rs[ch] == nil {
			buf.rs[ch] = resampler.new(.SINC_FASTEST, 1, nil)
		}
	}

	if samplerate == ANALYSIS_SAMPLE_RATE {
		for samples, ch in input {
			rb_produce(&buf.rings[ch], samples)
		}
	}
	else {
		ratio := ANALYSIS_SAMPLE_RATE / f32(samplerate)
		resize(&buf.resample_buf, int(linalg.ceil(f32(len(input[0])) * ratio)))

		for samples, ch in input {
			data := resampler.Data {
				data_in = raw_data(samples),
				data_out = raw_data(buf.resample_buf),
				input_frames = auto_cast len(samples),
				output_frames = auto_cast len(buf.resample_buf),
				src_ratio = f64(ratio),
			}

			resampler.process(buf.rs[ch], &data)
			rb_produce(&buf.rings[ch], buf.resample_buf[:])
		}
	}
}

analysis_consume :: proc(buf: ^Analysis_Buffer, time: f32, output: [][]f32) -> Audio_Spec {
	consume_count := int(linalg.ceil(time * ANALYSIS_SAMPLE_RATE))

	for o, ch in output {
		rb_consume(&buf.rings[ch], o, consume_count)
	}

	return {channels = buf.channels, samplerate = ANALYSIS_SAMPLE_RATE}
}

analysis_reset :: proc(buf: ^Analysis_Buffer) {
	for &ring in buf.rings {
		rb_reset(&ring)
	}

	for rs in buf.rs {
		if rs != nil do resampler.reset(rs)
	}
}
