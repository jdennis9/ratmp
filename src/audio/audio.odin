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
package analysis

import "core:sync"
import "core:math"
import "core:math/bits"
import glm "core:math/linalg/glsl"

import "src:../sdk"

import "src:bindings/fftw"

import "src:decoder"

calc_peak :: proc(samples: []f32) -> f32 {
	peak: f32 = 0
	for s in samples {
		peak = max(abs(s), peak)
	}
	return peak
}

calc_peaks :: proc(samples: [][$N]f32, channel_peaks: []f32) {
	assert(len(samples) == len(channel_peaks))
	channels := len(channel_peaks)

	for ch in 0..<channels {
		for s in samples[ch] {
			channel_peaks[ch] = max(abs(s), channel_peaks[ch])
		}
	}
}

Calc_Peaks_State :: struct {
	output_count: int,
	want_cancel: bool,
}

// Can set state.want_cancel to true asynchronously at any time to cancel this function
calc_peaks_over_time :: proc(dec: ^decoder.Decoder, output: []f32, state: ^Calc_Peaks_State) {
	assert(decoder.is_open(dec^))

	samplerate := dec.samplerate
	channels := dec.channels
	segment_size := dec.frame_count / len(output)
	buffer := make([]f32, segment_size * channels)
	defer delete(buffer)
	
	if state.want_cancel {
		return
	}
	
	for {
		if state.want_cancel || state.output_count >= len(output) {break}
		
		status := decoder.fill_buffer(dec, buffer, channels, samplerate)
		assert(status != .NoFile)
		peak := f32(0)

		for v in buffer {
			peak = max(abs(v), peak)
		}

		output[state.output_count] = peak
		state.output_count += 1

		if status == .Eof {break}
	}
}

calc_spectrum_frequencies :: proc(output: []f32) {
	// = the nth root of (20,000 / 50) where n is the number of bands
	freq_mul := math.pow(f32(400), f32(1.0/f32(len(output)-1)))

	// Calculate band frequencies
	i := f32(0)
	for &f in output {
		f = 50 * math.pow(freq_mul, i)
		i += 1
	}
}

// FFTW expects only one thread at a time to create plans
@(private="file")
_fftw_plan_lock: sync.Mutex

FFT_State :: struct {
	complex_buffer: []fftw.complex,
	real_buffer: []f32,
	window_size: int,
	plan: fftw.plan,
	plan_window_size: int,
}

fft_init :: proc(state: ^FFT_State, window_size: int) {
	state.complex_buffer = make([]fftw.complex, (window_size/2) + 1)
	state.real_buffer = make([]f32, (window_size/2) + 1)
	state.window_size = window_size
}

fft_set_window_size :: proc(state: ^FFT_State, window_size: int) {
	delete(state.complex_buffer)
	delete(state.real_buffer)
	state.complex_buffer = make([]fftw.complex, (window_size/2) + 1)
	state.real_buffer = make([]f32, (window_size/2) + 1)
	state.window_size = window_size
}

fft_process :: proc(state: ^FFT_State, input: []f32) {
	assert(len(input) == state.window_size)
	assert(state.complex_buffer != nil)
	assert(state.real_buffer != nil)

	frame_count := len(input)

	msb :: proc "contextless" (x: i32) -> u32 {
		return bits.log2(u32(x))
	}

	ln :: proc "contextless" (y: f32) -> (result: f32) {
		//return -1.7417939 + (2.8212026 + (-1.4699568 + (0.44717955 - 0.056570851 * x) * x) * x) * x
		log2: u32
		divisor, x: f32
		log2 = msb(auto_cast y)
		divisor = cast(f32) i32(1 << log2)
		x = y / divisor
		result = -1.7417939 + (2.8212026 + (-1.4699568 + (0.44717955 - 0.056570851 * x) * x) * x) * x
    	result += (f32(log2)) * 0.69314718 // ln(2) = 0.69314718
		return
	}

	log10 :: proc "contextless" (x: f32) -> f32 {
		return ln(x)/math.LN10
	}

	if state.plan == nil || state.window_size != state.plan_window_size {
		sync.lock(&_fftw_plan_lock)
		state.plan = fftw.plan_dft_r2c_1d(
			auto_cast frame_count, raw_data(input), raw_data(state.complex_buffer)
		)
		sync.unlock(&_fftw_plan_lock)

		if state.plan == nil do return
		state.plan_window_size = state.window_size
		fftw.execute(state.plan)
	}
	else {
		fftw.execute_dft_r2c(state.plan, raw_data(input), raw_data(state.complex_buffer))
	}

	for complex, i in state.complex_buffer {
		m := glm.length(complex)
		state.real_buffer[i] = log10(m) / math.PI
		state.real_buffer[i] = clamp(state.real_buffer[i], 0, 1)
	}
}

fft_extract_bands_from_slice :: proc(fft: []f32, window_size: int, frequencies: []f32, samplerate: f32, output: []f32) {
	if len(output) == 0 || len(fft) == 0 {return}
	freq_step := samplerate / f32(window_size)
	freq := freq_step
	band := 0

	for frame in fft[:] {
		defer freq += freq_step
		if freq > frequencies[band] {band = min(band + 1, len(output)-1)}
		output[band] = max(frame, output[band])
	}
}

fft_extract_bands :: proc(fft: FFT_State, frequencies: []f32, samplerate: f32, output: []f32) {
	fft_extract_bands_from_slice(fft.real_buffer[:], fft.window_size, frequencies, samplerate, output)
}

fft_destroy :: proc(fft: ^FFT_State) {
	delete(fft.real_buffer)
	delete(fft.complex_buffer)
	if fft.plan != nil {
		fftw.destroy_plan(fft.plan)
	}

	fft.real_buffer = nil
	fft.complex_buffer = nil
	fft.plan = nil
}

IFFT_State :: struct {
	plan: fftw.plan,
	plan_size: int,
	buffer: [dynamic]f32,
}

ifft_init :: proc(state: ^IFFT_State) {
}

ifft_destroy :: proc(state: ^IFFT_State) {
	delete(state.buffer)
	if state.plan != nil do fftw.destroy_plan(state.plan)
}

ifft_process :: proc(state: ^IFFT_State, input: [][2]f32) -> []f32 {
	output_size := (len(input) - 1) * 2
	resize(&state.buffer, output_size)

	if state.plan == nil || state.plan_size != output_size {
		state.plan_size = output_size

		if state.plan != nil do fftw.destroy_plan(state.plan)

		sync.lock(&_fftw_plan_lock)
		state.plan = fftw.plan_dft_c2r_1d(
			auto_cast output_size, raw_data(input), raw_data(state.buffer)
		)
		sync.unlock(&_fftw_plan_lock)

		fftw.execute(state.plan)
	}
	else {
		fftw.execute_dft_c2r(state.plan, raw_data(input), raw_data(state.buffer))
	}

	for &b in state.buffer {
		b /= f32(output_size)
	}

	return state.buffer[:]
}

deinterlace :: proc(input: []f32, output: [][]f32) {
	frame_count := len(output[0])
	channels := len(output)
	assert(len(input) / channels == frame_count)

	for frame in 0..<frame_count {
		for ch in 0..<channels {
			output[ch][frame] = input[(channels*frame) + ch]
		}
	}
}

interlace :: proc(input: [][]f32, output: []f32) {
	frame_count := len(input[0])
	channels := len(input)
	assert(len(output) / channels == frame_count)

	for ch in 0..<channels {
		for frame in 0..<frame_count {
			output[(channels*frame) + ch] = input[ch][frame]
		}
	}
}

make_window_hann :: proc(output: []f32) {
	N := f32(len(output))
	for i in 0..<len(output) {
		n := f32(i)
		output[i] = 0.5 * (1 - math.cos_f32((2 * math.PI * n) / (N - 1)))
	}
}

make_window_welch :: proc(output: []f32) {
	N := f32(len(output))
	N_2 := N/2

	for i in 0..<len(output) {
		n := f32(i)
		t := (n - N_2)/(N_2)
		output[i] = 1 - (t*t*t)
	}
}

make_window_osc :: proc(output: []f32) {
	N: f32
	margin := len(output)/10
	end_of_middle := len(output)-margin
	N = f32(margin)

	for i in 0..<margin {
		n := f32(i)
		output[i] = n/N
	}

	for i in margin..<end_of_middle {
		output[i] = 1
	}

	for i in end_of_middle..<len(output) {
		n := f32(i-end_of_middle)
		output[i] = 1 - (n/N)
	}
}

invert_window :: proc(w: []f32) {
	for &v in w do v = 1 / v
}

get_sdk_impl :: proc() -> sdk.Analysis_Procs {
	return sdk.Analysis_Procs {
		distribute_spectrum_frequencies = proc(output: []f32) {
			calc_spectrum_frequencies(output)
		},
		
		fft_new_state = proc(window_size: int) -> sdk.FFT_State {
			state := new(FFT_State)
			fft_init(state, window_size)
			return auto_cast state
		},

		fft_destroy_state = proc(state: sdk.FFT_State) {
			if state != nil do fft_destroy(auto_cast state)
		},

		fft_set_window_size = proc(state: sdk.FFT_State, size: int) {
			fft_set_window_size(auto_cast state, size)
		},

		fft_process = proc(state: sdk.FFT_State, input: []f32) -> []f32 {
			fft_process(auto_cast state, input)
			return (cast(^FFT_State) state).real_buffer
		},

		fft_extract_bands = proc(fft: []f32, input_size: int, freq_cutoffs: []f32, samplerate: f32, output: []f32) {
			fft_extract_bands_from_slice(fft, input_size, freq_cutoffs, samplerate, output)
		},
	}
}
