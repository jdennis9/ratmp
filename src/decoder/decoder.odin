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
package decoder

import "core:unicode/utf16"
import "core:math"
import "core:log"
import "core:fmt"

import sf "src:bindings/sndfile"
import src "src:bindings/samplerate"

Decoder :: struct {
	frame: int,
	frame_count: int,

	// Information about input file
	channels, samplerate: int,
	
	_stream: sf.Stream,
	_resampler: src.State,
	_in_to_out_sample_ratio: f32,
	_resample_quality: src.Converter_Type,
	_overflow: [dynamic]f32,
}

Decode_Status :: enum {
	NoFile,
	Complete,
	Eof,
}

open :: proc(dec: ^Decoder, file: string, resample_quality := src.Converter_Type.SINC_MEDIUM_QUALITY) -> bool {
	info: sf.Info

	close(dec)
	dec._resample_quality = resample_quality

	when ODIN_OS == .Windows {
		path: [512]u16
		utf16.encode_string(path[:511], file)
		dec._stream = sf.wchar_open(raw_data(path[:]), sf.MODE_READ, &info)
	}
	else {
		path: [512]u8

		// So -vet doesn't complain about utf16 package being unused
		utf16.is_surrogate(' ')

		copy(path[:511], file)
		dec._stream = sf.open(cstring(raw_data(path[:])), sf.MODE_READ, &info)
	}

	dec.samplerate = int(info.samplerate)
	dec.channels = int(info.channels)
	dec.frame_count = int(info.frames)

	return dec._stream != nil
}

close :: proc(dec: ^Decoder) {
	if dec._stream != nil {sf.close(dec._stream); dec._stream = nil}
	if dec._resampler != nil {src.delete(dec._resampler); dec._resampler = nil}
	delete(dec._overflow)
	dec.frame = 0
	dec._overflow = nil
}

is_open :: proc(dec: Decoder) -> bool {
	return dec._stream != nil
}

destroy :: proc(dec: Decoder) {
	if dec._stream != nil {sf.close(dec._stream)}
	src.delete(dec._resampler)
	delete(dec._overflow)
}

@private
_convert_channels :: proc(dst: []f32, dst_channels: int, src_channels: int) {
	out_samples := len(dst)
	out_frames := out_samples / dst_channels

	src := make([]f32, out_frames * min(src_channels, dst_channels))
	defer delete(src)
	copy(src[:], dst[:])

	assert(dst_channels != src_channels)

	if src_channels == 1 {
		dst_i: int
		for f in src {
			for ch in 0..<dst_channels {
				dst[dst_i+ch] = f
			}
			dst_i += dst_channels
		}
	}
	else if dst_channels == 1 {
		src_i: int
		for i in 0..<out_samples {
			max_sample: f32
			abs_max: f32
			for ch in 0..<src_channels {
				if abs(src[src_i+ch]) > abs_max {
					max_sample = src[src_i+ch]
					abs_max = abs(max_sample)
				}
			}

			dst[i] = max_sample
			src_i += 2
		}
	}
	else {
		panic("Unsupported channel conversion")
	}
}

@private
_decode_packet :: proc(dec: ^Decoder, output: []f32, samplerate, channels: int) -> (out_frames_read: int, out_frames_written: int) {
	needs_resampling := dec.samplerate != samplerate
	output_frames := len(output) / channels

	if !needs_resampling {
		frames_read := sf.readf_float(dec._stream, raw_data(output), sf.count_t(output_frames))
		if channels != dec.channels {
			_convert_channels(output, channels, dec.channels)
		}
		return auto_cast frames_read, auto_cast frames_read
	}

	in_to_out_sample_ratio := f32(samplerate) / f32(dec.samplerate)
	input_frames := cast(i32) math.ceil(f32(output_frames) / in_to_out_sample_ratio)
	raw_buffer: []f32 = make([]f32, input_frames * cast(i32) max(channels, dec.channels))
	defer delete(raw_buffer)

	if dec._resampler == nil {
		error: i32
		dec._resampler = src.new(dec._resample_quality, auto_cast channels, &error)
		dec._in_to_out_sample_ratio = in_to_out_sample_ratio
	}

	if in_to_out_sample_ratio != dec._in_to_out_sample_ratio {
		dec._in_to_out_sample_ratio = in_to_out_sample_ratio
		src.set_ratio(dec._resampler, auto_cast in_to_out_sample_ratio)
	}

	sf.readf_float(dec._stream, raw_data(raw_buffer), sf.count_t(input_frames))

	if dec.channels != channels {
		_convert_channels(raw_buffer[:], channels, dec.channels)
	}

	rs := src.Data {
		data_in = raw_data(raw_buffer),
		data_out = raw_data(output),
		input_frames = auto_cast input_frames,
		output_frames = auto_cast output_frames,
		src_ratio = f64(in_to_out_sample_ratio),
	}

	if process_error := src.process(dec._resampler, &rs); process_error != 0 {
		log.warn("src.process returned", process_error)
	}

	if rs.output_frames_gen != auto_cast output_frames {
		fmt.println("Wanted", output_frames, "frames, got", rs.output_frames_gen)
	}

	return auto_cast rs.input_frames_used, auto_cast rs.output_frames_gen
}

fill_buffer :: proc(dec: ^Decoder, output: []f32, channels: int, samplerate: int) -> (status: Decode_Status) {
	if dec._stream == nil {
		return .NoFile
	}

	
	packet: [4800]f32
	frames_wanted := len(output) / channels
	frames_decoded := 0
	status = .Complete
	
	if len(dec._overflow) > 0 {
		overflow_samples := min(len(dec._overflow), len(output))
		overflow_frames := overflow_samples / channels
		
		copy(output, dec._overflow[:overflow_samples])
		
		if overflow_samples < len(dec._overflow) {
			remove_range(&dec._overflow, 0, overflow_samples)
		}
		else {
			clear(&dec._overflow)
		}
		
		frames_decoded += overflow_frames
	}
	
	for (frames_decoded < frames_wanted) && (status != .Eof) {
		packet_frames_in, packet_frames := _decode_packet(dec, packet[:], samplerate, channels)

		if packet_frames == 0 {
			status = .Eof
			break
		}

		overflow_frames := frames_decoded + packet_frames - frames_wanted

		if overflow_frames > 0 {
			copy(output[frames_decoded*channels:], packet[:(packet_frames-overflow_frames)*channels])
			resize(&dec._overflow, overflow_frames * channels)
			copy(dec._overflow[:], packet[(packet_frames-overflow_frames)*channels : packet_frames*channels])
		}
		else {
			copy(output[frames_decoded*channels:], packet[:])
		}

		frames_decoded += packet_frames

		dec.frame += packet_frames_in

		if dec.frame >= dec.frame_count {
			status = .Eof
			break
		}
	}

	return
}

seek :: proc(dec: ^Decoder, second: int) {
	if dec._stream == nil {return}

	frame := sf.count_t(dec.samplerate) * sf.count_t(second)
	sf.seek(dec._stream, frame, .SEEK_SET)
	dec.frame = int(frame)
	
	clear(&dec._overflow)

	if dec._resampler != nil {
		src.reset(dec._resampler)
	}
}

get_second :: proc(dec: Decoder) -> int {
	if dec._stream == nil {return 0}
	return dec.frame / int(dec.samplerate)
}

get_duration :: proc(dec: Decoder) -> int {
	if dec._stream == nil {return 0}
	return dec.frame_count / dec.samplerate
}
