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
package decoder;

import "core:unicode/utf16";
import "core:math";
import "core:log";

import sf "bindings:sndfile";
import src "bindings:samplerate";


Decoder :: struct {
	stream: sf.Stream,
	info: sf.Info,
	resampler: src.State,
	frame: int,
};

Decode_Status :: enum {
	NO_FILE,
	COMPLETE,
	EOF,
};

open :: proc(dec: ^Decoder, file: string) -> bool {
	close(dec);
	when ODIN_OS == .Windows {
		path: [512]u16;
		utf16.encode_string(path[:511], file);
		dec.stream = sf.wchar_open(raw_data(path[:]), sf.MODE_READ, &dec.info);
	}
	else {
		path: [512]u8;
		copy(path[:511], file);
		dec.stream = sf.open(cstring(raw_data(path[:])), sf.MODE_READ, &dec.info);
	}
	return dec.stream != nil;
}

close :: proc(dec: ^Decoder) {
	if dec.stream != nil {sf.close(dec.stream); dec.stream = nil;}
	if dec.resampler != nil {src.delete(dec.resampler); dec.resampler = nil;}
	dec.frame = 0;
}

fill_buffer :: proc(dec: ^Decoder, output: []f32, samplerate: int, channels: int) -> (status: Decode_Status) {
	if dec.stream == nil {
		return .NO_FILE;
	}

	status = .COMPLETE;

	needs_resampling := dec.info.samplerate != cast(i32) samplerate || dec.info.channels != cast(i32) channels;
	output_frames := len(output) / channels;

	if !needs_resampling {
		frames_read := sf.readf_float(dec.stream, raw_data(output), sf.count_t(output_frames));
		if (frames_read < i64(output_frames)) {return .EOF;}
		dec.frame += int(frames_read);
		return .COMPLETE;
	}

	if dec.resampler == nil {
		error: i32;
		dec.resampler = src.new(.SINC_MEDIUM_QUALITY, 2, &error);
	}

	in_to_out_sample_ratio := f32(samplerate) / f32(dec.info.samplerate);
	input_frames := cast(i32) math.ceil(f32(output_frames) / in_to_out_sample_ratio);
	raw_buffer: []f32 = make([]f32, input_frames * dec.info.channels);
	defer delete(raw_buffer);

	frames_read := sf.readf_float(dec.stream, raw_data(raw_buffer), sf.count_t(input_frames));

	if (frames_read < sf.count_t(input_frames)) {
		status = .EOF;
	}

	rs := src.Data {
		data_in = raw_data(raw_buffer),
		data_out = raw_data(output),
		input_frames = auto_cast input_frames,
		output_frames = auto_cast output_frames,
		src_ratio = f64(in_to_out_sample_ratio),
	};

	src.process(dec.resampler, &rs);

	dec.frame += cast(int) frames_read;

	return;
}

seek :: proc(dec: ^Decoder, second: int) {
	if dec.stream == nil {
		return;
	}

	frame := sf.count_t(dec.info.samplerate) * sf.count_t(second);
	sf.seek(dec.stream, frame, .SEEK_SET);
	dec.frame = int(frame);
}

get_second :: proc(dec: ^Decoder) -> int {
	if dec.stream == nil {return 0}
	return dec.frame / int(dec.info.samplerate);
}

get_duration :: proc(dec: ^Decoder) -> int {
	if dec.stream == nil {return 0}
	return int(dec.info.frames) / int(dec.info.samplerate);
}
