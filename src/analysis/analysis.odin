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
	//base_freq := f32(50)
	i := f32(0)
	for &f in output {
		f = 50 * math.pow(freq_mul, i)
		i += 1
	}
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
    	result += (f32(log2)) * 0.69314718; // ln(2) = 0.69314718
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

calc_spectrum :: proc(
	input: []f32,
	frequencies: []f32,
	// Length of output determines number of bands
	output: []f32,
	samplerate: f32,
	fft_buffer: ^[dynamic][2]f32,
) {
	assert(len(frequencies) == len(output))
	frame_count := len(input)

	// fft input needs to be an even number length
	if frame_count % 2 != 0 {frame_count -= 1}
	cplx_count := (frame_count/2) + 1

	//buffer := make([]fftw.complex, cplx_count)
	resize(fft_buffer, cplx_count)
	defer clear(fft_buffer)
	plan := fftw.plan_dft_r2c_1d(auto_cast frame_count, raw_data(input), raw_data(fft_buffer[:]), 0)
	if plan == nil {return}
	defer fftw.destroy_plan(plan)

	fftw.execute(plan)

	freq_step := samplerate / f32(frame_count)
	scale_factor := 1 / f32(frame_count)
	freq := freq_step

	for frame in fft_buffer[1:] {
		band := 0
		defer freq += freq_step

		//freq := (f32(i+1) * samplerate) / f32(frame_count)
		//scale_factor = 1 / f32(frame_count - i)

		// @Optimize: Find algoritm to find this without needing to iterate
		for band < (len(output)-1) && freq > frequencies[band] {
			band += 1
		}

		//mag := math.log10(glm.dot(frame, frame) * scale_factor) + 0.5
		//mag := math.log10(glm.length(frame)) * scale_factor
		//mag := glm.dot(frame, frame) * scale_factor
		//mag := (math.log10(glm.dot(frame, frame)) + 2) / 2.6
		//mag := math.log10(glm.length(frame)) / 2.6
		//mag = clamp(mag, 0, 1)
		//mag := glm.length(frame * scale_factor) * math.PI
	
		d := glm.dot(frame, frame)
		if d < 0 {continue}
		mag := math.log10(d) * scale_factor * 1400
		output[band] = max(mag, output[band])
	}

}
