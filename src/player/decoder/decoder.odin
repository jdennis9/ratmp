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

import sf "bindings:sndfile"
import src "bindings:samplerate"

Decoder :: struct {
	stream: sf.Stream,
	info: sf.Info,
	resampler: src.State,
	frame: int,
	in_to_out_sample_ratio: f32,
	resample_quality: src.Converter_Type,
	overflow: [dynamic]f32,
}

Decode_Status :: enum {
	NoFile,
	Complete,
	Eof,
}

open :: proc(dec: ^Decoder, file: string, resample_quality := src.Converter_Type.SINC_MEDIUM_QUALITY) -> bool {
	close(dec)
	dec.resample_quality = resample_quality
	when ODIN_OS == .Windows {
		path: [512]u16
		utf16.encode_string(path[:511], file)
		dec.stream = sf.wchar_open(raw_data(path[:]), sf.MODE_READ, &dec.info)
	}
	else {
		path: [512]u8
		copy(path[:511], file)
		dec.stream = sf.open(cstring(raw_data(path[:])), sf.MODE_READ, &dec.info)
	}
	return dec.stream != nil
}

close :: proc(dec: ^Decoder) {
	if dec.stream != nil {sf.close(dec.stream); dec.stream = nil}
	if dec.resampler != nil {src.delete(dec.resampler); dec.resampler = nil}
	clear(&dec.overflow)
	dec.frame = 0
}

destroy :: proc(dec: Decoder) {
	if dec.stream != nil {sf.close(dec.stream)}
	src.delete(dec.resampler)
	delete(dec.overflow)
}

@private
_decode_packet :: proc(dec: ^Decoder, output: []f32, samplerate, channels: int) -> int {
	needs_resampling := dec.info.samplerate != cast(i32) samplerate || dec.info.channels != cast(i32) channels
	output_frames := len(output) / channels

	if !needs_resampling {
		frames_read := sf.readf_float(dec.stream, raw_data(output), sf.count_t(output_frames))
		return auto_cast frames_read
	}

	in_to_out_sample_ratio := f32(samplerate) / f32(dec.info.samplerate)
	input_frames := cast(i32) math.ceil(f32(output_frames) / in_to_out_sample_ratio)
	raw_buffer: []f32 = make([]f32, input_frames * dec.info.channels)
	defer delete(raw_buffer)

	if dec.resampler == nil {
		error: i32
		dec.resampler = src.new(dec.resample_quality, auto_cast channels, &error)
		dec.in_to_out_sample_ratio = in_to_out_sample_ratio
	}

	if in_to_out_sample_ratio != dec.in_to_out_sample_ratio {
		dec.in_to_out_sample_ratio = in_to_out_sample_ratio
		src.set_ratio(dec.resampler, auto_cast in_to_out_sample_ratio)
	}

	sf.readf_float(dec.stream, raw_data(raw_buffer), sf.count_t(input_frames))

	rs := src.Data {
		data_in = raw_data(raw_buffer),
		data_out = raw_data(output),
		input_frames = auto_cast input_frames,
		output_frames = auto_cast output_frames,
		src_ratio = f64(in_to_out_sample_ratio),
	}

	if process_error := src.process(dec.resampler, &rs); process_error != 0 {
		log.warn("src.process returned", process_error)
	}

	if rs.output_frames_gen != auto_cast output_frames {
		fmt.println("Wanted", output_frames, "frames, got", rs.output_frames_gen)
	}

	return auto_cast rs.output_frames_gen
}

fill_buffer :: proc(dec: ^Decoder, output: []f32, samplerate: int, channels: int) -> (status: Decode_Status) {
	if dec.stream == nil {
		return .NoFile
	}

	packet: [4800]f32
	frames_wanted := len(output) / channels
	frames_decoded := 0
	status = .Complete

	if len(dec.overflow) > 0 {
		overflow_samples := min(len(dec.overflow), len(output))
		overflow_frames := overflow_samples / channels

		copy(output, dec.overflow[:overflow_samples])

		if overflow_samples < len(dec.overflow) {
			remove_range(&dec.overflow, 0, overflow_samples)
		}
		else {
			clear(&dec.overflow)
		}

		frames_decoded += overflow_frames
	}

	for (frames_decoded < frames_wanted) && (status != .Eof) {
		packet_frames := _decode_packet(dec, packet[:], samplerate, channels)

		if packet_frames == 0 {
			status = .Eof
			break
		}

		overflow_frames := frames_decoded + packet_frames - frames_wanted

		if overflow_frames > 0 {
			copy(output[frames_decoded*channels:], packet[:(packet_frames-overflow_frames)*channels])
			resize(&dec.overflow, overflow_frames * channels)
			copy(dec.overflow[:], packet[(packet_frames-overflow_frames)*channels : packet_frames*channels])
		}
		else {
			copy(output[frames_decoded*channels:], packet[:])
		}

		frames_decoded += packet_frames
	}

	dec.frame += frames_decoded

	return
}

seek :: proc(dec: ^Decoder, second: int) {
	if dec.stream == nil {
		return
	}

	frame := sf.count_t(dec.info.samplerate) * sf.count_t(second)
	sf.seek(dec.stream, frame, .SEEK_SET)
	dec.frame = int(frame)
}

get_second :: proc(dec: Decoder) -> int {
	if dec.stream == nil {return 0}
	return dec.frame / int(dec.info.samplerate)
}

get_duration :: proc(dec: Decoder) -> int {
	if dec.stream == nil {return 0}
	return int(dec.info.frames) / int(dec.info.samplerate)
}
