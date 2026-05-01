package dsp

import "core:mem"
import "core:fmt"
import "core:math/linalg"
MAX_CHANNELS :: 2

Process_Params_Hard_Limit :: struct {
	attack_ms: f32,
	limit: f32,
}

Process_Params :: struct {
	limiter: Maybe(Limiter_Params),
}

Process_State :: struct {
	limiter: Limiter,
}

@private
delay_write :: proc(output: []f32, value: f32, index: int, delay: int) {
	i := max(index - delay, 0)
	output[i] = value
}

post_process :: proc(
	state: ^Process_State,
	params: Process_Params,
	audio: [][]f32,
	samplerate: f32,
	temp_allocator: mem.Allocator,
) {
	sample_delta := (1/samplerate)*1000

	peaks: [MAX_CHANNELS]f32
	peak_indices: [MAX_CHANNELS]int

	for samples, ch in audio {
		peak: f32 = 0
		for p, i in samples {
			if abs(p) > peak {
				peak = abs(p)
				peak_indices[ch] = i
			}
		}
		peaks[ch] = peak
	}

	if params.limiter != nil {
		limiter_process(&state.limiter, params.limiter.?, audio, samplerate)
	}
}
