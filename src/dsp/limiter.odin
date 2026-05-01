package dsp

import "core:fmt"
import "core:math/linalg"
import "core:sys/linux"
// -----------------------------------------------------------------------------
// Basic limiter
// -----------------------------------------------------------------------------

LIMITER_PANIC_GAIN :: 0.2
LIMITER_LOOKAHEAD_SAMPLES :: 128
LIMITER_BLOCK_SIZE :: 512
LIMITER_PANIC_HOLD_TIME :: 0.020

Limiter_Params :: struct {
	limit: f32,
	release_ms: f32,
}

Limiter :: struct {
	panic_hold_samples: int,
	safety_gain: f32,
	current_gain: f32,
	target_gain: f32,
	last_jump_peak: f32,
}

ms_to_samples :: proc(ms, samplerate: f32) -> int {
	return int(ms * samplerate * 0.001)
}

limiter_reset :: proc(l: ^Limiter) {
	l.panic_hold_samples = 0
}

// Splits into blocks and processes each block with limiter_process_block
limiter_process :: proc(
	l: ^Limiter,
	params: Limiter_Params,
	audio: [][]f32,
	samplerate: f32,
) {
	sample_count := len(audio[0])
	channel_count := len(audio)
	block_count := sample_count / LIMITER_BLOCK_SIZE
	if sample_count % LIMITER_BLOCK_SIZE != 0 do block_count += 1

	for i in 0..<block_count {
		block: [MAX_CHANNELS][]f32
		block_size := min(LIMITER_BLOCK_SIZE, sample_count - (i * LIMITER_BLOCK_SIZE))

		for ch in 0..<channel_count {
			block[ch] = audio[ch][(i * LIMITER_BLOCK_SIZE):][:block_size]
		}

		limiter_process_block(l, params, block[:channel_count], samplerate)
	}
}

limiter_process_block :: proc(
	l: ^Limiter,
	params: Limiter_Params,
	audio: [][]f32,
	samplerate: f32,
) {
	detect_jump :: proc(
		audio: [][]f32,
	) -> f32 {
		peak: f32 = 0
		
		lookahead := min(len(audio[0]), LIMITER_LOOKAHEAD_SAMPLES)

		for samples in audio {
			for sample in samples[:lookahead] {
				peak = max(abs(sample), peak)
			}
		}

		peak = max(peak, 0.01)

		return peak
	}

	jump_detection :: proc(
		l: ^Limiter,
		audio: [][]f32,
		samplerate: f32,
	) {
		sample_count := len(audio[0])
		jump := detect_jump(audio)
		delta := jump - l.last_jump_peak
		block_ms := (f32(sample_count) * 1000) / samplerate
		step := delta / max(block_ms, 0.001)

		jump_detected := delta > 2 || step > 1.1

		l.last_jump_peak = jump
		fmt.println(delta, step)

		if jump_detected {
			l.safety_gain = LIMITER_PANIC_GAIN
			l.panic_hold_samples = int(LIMITER_PANIC_HOLD_TIME * samplerate)
		}
	}

	apply_safety_gain :: proc(
		l: ^Limiter,
		audio: [][]f32,
	) {
		sample_count := len(audio[0])

		if l.panic_hold_samples > 0 {
			l.panic_hold_samples -= sample_count
		}
		else {
			l.safety_gain = min(1, l.safety_gain + 0.002)
		}

		for samples in audio {
			for &sample in samples {
				sample *= l.safety_gain
			}
		}
	}

	apply_release_smoothing :: proc(
		l: ^Limiter,
		p: Limiter_Params,
		target_gain: f32,
		audio: [][]f32,
		samplerate: f32,
	) {
		sample_count := len(audio[0])
		release_seconds := 0.001 * p.release_ms
		alpha := linalg.exp(-f32(sample_count) / (release_seconds * samplerate))

		l.current_gain = alpha * l.current_gain + (1 - alpha) * target_gain
		fmt.println(l.current_gain, target_gain)
	}

	apply_loudness_correction :: proc(
		l: ^Limiter,
		p: Limiter_Params,
		audio: [][]f32,
		samplerate: f32,
	) {
		sample_count := len(audio[0])
		channel_count := len(audio)
		target_gain: f32

		rms: f32 = 0

		for samples in audio {
			sum: f32 = 0

			for sample in samples {
				sum += sample * sample
			}

			rms += linalg.sqrt(sum / f32(sample_count))
		}

		rms = max(rms / f32(channel_count), 0.01)

		target_gain = clamp(p.limit - rms, -5, 1)

		apply_release_smoothing(l, p, amp_to_gain(target_gain), audio, samplerate)
		gain_to_apply := gain_to_amp(l.current_gain)
		
		for samples in audio {
			for &sample in samples {
				sample *= gain_to_apply
			}
		}
	}

	jump_detection(l, audio, samplerate)
	apply_safety_gain(l, audio)
	apply_loudness_correction(l, params, audio, samplerate)
}
