/*
    RAT MP - A cross-platform, extensible music player
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
package analysis

import "core:math"
import "core:math/bits"
import glm "core:math/linalg/glsl"

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

		output[state.output_count] = clamp(peak, 0, 1)
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

FFT_State :: struct {
	complex_buffer: []fftw.complex,
	real_buffer: []f32,
	plan: fftw.plan,
	window_size: int,
}

fft_init :: proc(state: ^FFT_State, window_size: int) {
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
    	result += (f32(log2)) * 0.69314718; // ln(2) = 0.69314718
		return
	}

	log10 :: proc "contextless" (x: f32) -> f32 {
		return ln(x)/math.LN10
	}

	if state.plan == nil {
		state.plan = fftw.plan_dft_r2c_1d(auto_cast frame_count, raw_data(input), raw_data(state.complex_buffer), 0)
		if state.plan == nil {return}
		fftw.execute(state.plan)
	}
	else {
		fftw.execute_dft_r2c(state.plan, raw_data(input), raw_data(state.complex_buffer))
	}

	scale_factor := 1 / f32(state.window_size)

	// Scale and convert complex values to real in 0-1 range
	for complex, i in state.complex_buffer[1:] {	
		state.real_buffer[i] = 0
		d := glm.dot(complex, complex)
		if d < 1 {continue}
		// @TODO: Figure out good scaling for this
		state.real_buffer[i] = log10(d) * scale_factor * 1500
	}
}

fft_extract_bands :: proc(fft: FFT_State, frequencies: []f32, samplerate: f32, output: []f32) {
	if len(output) == 0 || len(fft.real_buffer) == 0 {return}
	freq_step := samplerate / f32(fft.window_size)
	freq := freq_step
	band := 0

	for frame in fft.real_buffer[1:] {
		defer freq += freq_step
		if freq > frequencies[band] {band = min(band + 1, len(output)-1)}
		output[band] = max(frame, output[band])
	}
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

Spectrum_Analyser :: struct {
	buffer: []fftw.complex,
	plan: fftw.plan,
	window_size: int,
	scale: f32,
}

spectrum_analyser_init :: proc(state: ^Spectrum_Analyser, window_size: int, scale: f32) {
	state.buffer = make([]fftw.complex, (window_size/2) + 1)
	state.window_size = window_size
	state.scale = scale
}

spectrum_analyser_calc :: proc(state: ^Spectrum_Analyser, input: []f32, frequencies: []f32, output: []f32, samplerate: f32) {
	assert(len(input) == state.window_size)
	assert(state.buffer != nil)

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

	if state.plan == nil {
		state.plan = fftw.plan_dft_r2c_1d(auto_cast frame_count, raw_data(input), raw_data(state.buffer), 0)
		if state.plan == nil {return}
		fftw.execute(state.plan)
	}
	else {
		fftw.execute_dft_r2c(state.plan, raw_data(input), raw_data(state.buffer))
	}

	freq_step := samplerate / f32(frame_count)
	scale_factor := 1 / f32(frame_count)
	freq := freq_step
	band := 0

	for &frame in state.buffer[1:] {
		defer freq += freq_step

		if freq > frequencies[band] {band = min(band + 1, len(output)-1)}
	
		d := glm.dot(frame, frame)
		if d <= 10 {continue}
		// @TODO: Figure out good scaling for this
		mag := log10(d) * scale_factor * 1500

		output[band] = max(mag, output[band])
	}
}

spectrum_analyser_destroy :: proc(state: ^Spectrum_Analyser) {
	delete(state.buffer)
	fftw.destroy_plan(state.plan)
}

