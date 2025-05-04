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
package analysis

import glm "core:math/linalg/glsl"
import "core:math"
import "core:thread"
import "core:slice"
import "core:sync"

import kiss "bindings:kissfft"

import "player:playback"
import "player:decoder"
import "player:library"

PEAK_ROUGHNESS :: 15
SLOW_PEAK_ROUGHNESS :: 2
MAX_CHANNELS :: playback.MAX_CHANNELS
SPECTRUM_BANDS :: 20

SPECTRUM_BAND_OFFSETS := [?]int {
    0,
    50, 70, 100, 130,
    180, 250, 330, 450,
	620, 850, 1200, 1600,
	2200, 3000, 4100, 5600,
    7700, 11000, 14000, 20000,
}

Spectrum :: struct {
	peaks: [SPECTRUM_BANDS]f32,
	slow_peaks: [SPECTRUM_BANDS]f32,
}

Waveform_Preview :: struct {
	dec: decoder.Decoder,
	output: [dynamic]f32,
	out_count: int,
	want_cancel: bool,
	track: library.Track_ID,
	thread: ^thread.Thread,
	lock: sync.Mutex,
}

@private
this: struct {
	peaks: [MAX_CHANNELS]f32,
	buffer: playback.Output_Buffer,
	spectrum: Spectrum,
	waveform_preview: Waveform_Preview,
	recalc_peak: bool,
	recalc_spectrum: bool,
	recalc_wave_preview: bool,

	fft_cfg: kiss.fftr_cfg,
	fft_cfg_frame_count: int,
}

update :: proc(lib: library.Library, pb: playback.State, delta: f32, window_length: f32) {
	playback.update_output_copy_buffer(pb, &this.buffer)
	view := playback.get_output_buffer_view(&this.buffer, int(window_length*f32(this.buffer.samplerate)))
	
	if len(view.data[0]) == 0 {
		for ch in 0..<MAX_CHANNELS {
			this.peaks[ch] = glm.lerp(this.peaks[ch], 0, delta*PEAK_ROUGHNESS)
		}
		
		return
	}
	
	hann_view := _hann_window(view)
	defer _free_windowed_view(hann_view)

	lerp_t := clamp(delta*PEAK_ROUGHNESS, 0, 1)
	slow_lerp_t := clamp(delta*SLOW_PEAK_ROUGHNESS, 0, 1)
	
	// -------------------------------------------------------------------------
	// Peak
	// -------------------------------------------------------------------------
	if this.recalc_peak {
		this.recalc_peak = false
		for ch in 0..<view.channels {
			peak: f32
			for sample in view.data[ch] {
				peak = max(peak, sample)
			}

			if math.is_nan(this.peaks[ch]) {this.peaks[ch] = 0}
			this.peaks[ch] = glm.lerp(this.peaks[ch], peak, lerp_t)
		}

	}

	// -------------------------------------------------------------------------
	// Spectrum
	// -------------------------------------------------------------------------
	if this.recalc_spectrum {
		this.recalc_spectrum = false
		spectrum := _calc_spectrum(view)
		for peak, index in spectrum.peaks {
			if math.is_nan(this.spectrum.peaks[index]) {
				this.spectrum.peaks[index] = 0
			}
			this.spectrum.peaks[index] = math.lerp(this.spectrum.peaks[index], peak, lerp_t)
			this.spectrum.slow_peaks[index] = math.lerp(this.spectrum.slow_peaks[index], peak, slow_lerp_t)
			this.spectrum.slow_peaks[index] = max(this.spectrum.slow_peaks[index], this.spectrum.peaks[index])
		}
	}

	// -------------------------------------------------------------------------
	// Wave preview
	// -------------------------------------------------------------------------
	if this.recalc_wave_preview {
		this.recalc_wave_preview = false
		data := &this.waveform_preview
		track := pb.playing_track
		if track != 0 && track != data.track {
			if data.thread != nil {
				data.want_cancel = true
				thread.join(data.thread)
				thread.destroy(data.thread)
				data.thread = nil
				data.want_cancel = false
				decoder.close(&data.dec)
			}
			
			path_buf: [512]u8
			data.track = track
			path := library.get_track_path(lib, track, path_buf[:])

			if decoder.open(&data.dec, path, .LINEAR) {
				data.thread = thread.create_and_start(_waveform_preview_thread_proc, context)
				if data.thread == nil {
					decoder.close(&data.dec)
				}
			}
		}
	}
}

shutdown :: proc() {
	kiss.fftr_free(this.fft_cfg)
}

get_channel_peaks :: proc() -> []f32 {
	this.recalc_peak = true
	return this.peaks[:this.buffer.channels]
}

get_spectrum :: proc() -> Spectrum {
	this.recalc_spectrum = true
	return this.spectrum
}

get_waveform_preview :: proc() -> (samples: []f32) {
	this.recalc_wave_preview = true
	sync.lock(&this.waveform_preview.lock)
	defer sync.unlock(&this.waveform_preview.lock)
	if len(this.waveform_preview.output) > 0 {
		return this.waveform_preview.output[:]
	}

	return nil
}

@private
_hann_window :: proc(view: playback.Output_Buffer) -> (window: playback.Output_Buffer) {
	window = view
	n := len(view.data[0])

	for ch in 0..<window.channels {
		window.data[ch] = make([]f32, n)
		for i in 0..<len(view.data[ch]) {
			mul := 0.5 * (1 - math.cos_f32(2 * math.PI * f32(i) / f32(n - 1)))
			window.data[ch][i] = view.data[ch][i] * mul
		}
	}

	return
}

@private
_free_windowed_view :: proc(view: playback.Output_Buffer) {
	for ch in 0..<view.channels {
		delete(view.data[ch])
	}
}

@private
_calc_spectrum :: proc(view: playback.Output_Buffer) -> (spectrum: Spectrum) {
	frame_count := len(view.data[0])
	// Frame count must be even for kissfft
	if frame_count % 2 != 0 {frame_count -= 1}

	if this.fft_cfg == nil || frame_count != this.fft_cfg_frame_count {
		if this.fft_cfg != nil {
			kiss.fftr_free(this.fft_cfg)
		}
		this.fft_cfg_frame_count = frame_count
		this.fft_cfg = kiss.fftr_alloc(auto_cast this.fft_cfg_frame_count, 0, nil, nil)
	}

	if this.fft_cfg == nil {
		return
	}

	out_count := (frame_count / 2) + 1
	freq_step := 22050 / frame_count

	buffer := make([]kiss.fft_cpx, out_count)
	defer delete(buffer)

	kiss.fftr(this.fft_cfg, &view.data[0][0], &buffer[0])

	for i in 0..<out_count {
		freq := i * freq_step
		band := 0

		for _ in 0..<SPECTRUM_BANDS-1 {
			if freq >= SPECTRUM_BAND_OFFSETS[band] && freq <= SPECTRUM_BAND_OFFSETS[band+1] {
				break
			}
			band += 1
		}

		frame := buffer[i]
		mag := math.log10(math.sqrt((frame.r * frame.r) + (frame.i * frame.i)))
		if (mag < 0) {mag = 0}

		spectrum.peaks[band] = max(mag, spectrum.peaks[band])
	}

	for &peak in spectrum.peaks {
		peak /= 2.6
	}

	return
}

@private
_waveform_preview_thread_proc :: proc() {
	data := &this.waveform_preview	
	dec := &data.dec
	data.out_count = 0
	
	samplerate := dec.samplerate
	channels := dec.channels
	segment_size := dec.frame_count / 1080
	buffer := make([]f32, segment_size * channels)
	defer delete(buffer)
	
	sync.lock(&this.waveform_preview.lock)
	resize(&data.output, (dec.frame_count / segment_size))
	sync.unlock(&this.waveform_preview.lock)

	if data.want_cancel {return}

	slice.fill(data.output[:], 0)

	for {
		status := decoder.fill_buffer(dec, buffer, int(samplerate), int(channels))
		peak := f32(0)

		for v in buffer {
			peak = max(abs(v), peak)
		}

		data.output[data.out_count] = clamp(peak, 0, 1)
		data.out_count += 1

		if data.want_cancel || status == .Eof || data.out_count >= len(data.output) {return}
	}
}
