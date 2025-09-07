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
package decoder_v2

import "core:strings"

import ffmpeg "src:bindings/ffmpeg_2"

Decode_Status :: enum {
	NoFile,
	Complete,
	Eof,
}

File_Info :: struct {
	codec: [64]u8,
	samplerate: int,
	channels: int,
}

Decoder :: struct {
	ff: ^ffmpeg.Context,
	overflow: [dynamic]f32,
	overflow_samplerate: int,
	overflow_channels: int,
	samplerate: int,
	channels: int,
	frame_index: int,
	frame_count: int,
	duration_seconds: i64,
	is_open: bool,
}

open :: proc(dec: ^Decoder, filename_native: string, info: ^File_Info) -> (ok: bool) {
	filename := strings.clone_to_cstring(filename_native)
	defer delete(filename)
	file_info: ffmpeg.File_Info

	close(dec)

	if dec.ff == nil {
		dec.ff = ffmpeg.create_context()
	}

	ffmpeg.open_input(dec.ff, filename, &file_info)

	dec.samplerate = auto_cast file_info.spec.samplerate
	dec.channels = auto_cast file_info.spec.channels
	dec.frame_index = 0
	dec.duration_seconds = file_info.total_frames / auto_cast file_info.spec.samplerate
	dec.frame_count = auto_cast file_info.total_frames

	if info != nil {
		info^ = {}
		copy(info.codec[:], "TODO")
		info.samplerate = dec.samplerate
		info.channels = dec.channels
	}
	
	dec.is_open = true
	ok = true
	return
}

close :: proc(dec: ^Decoder) {
	dec.is_open = false
	dec.frame_index = 0
	dec.frame_count = 0

	delete(dec.overflow)
	dec.overflow = nil

	ffmpeg.close_input(dec.ff)
}

is_open :: proc(dec: Decoder) -> bool {
	return dec.is_open
}

@private
_decode_packet :: proc(dec: ^Decoder, output: ^[dynamic]f32, channels, samplerate: int) -> (read: int, written: int, eof: bool) {
	pkt: ffmpeg.Packet
	spec: ffmpeg.Audio_Spec
	spec.channels = auto_cast channels
	spec.samplerate = auto_cast samplerate

	if ffmpeg.decode_packet(dec.ff, &spec, &pkt) == .Eof {
		eof = true
		return
	}

	defer ffmpeg.free_packet(&pkt)

	read = auto_cast pkt.frames_in
	written = auto_cast pkt.frames_out

	resize(output, pkt.frames_out * auto_cast channels)

	for frame in 0..<int(pkt.frames_out) {
		for ch in 0..<channels {
			output[(frame*channels) + ch] = pkt.data[ch][frame]
		}
	}

	return
}

fill_buffer :: proc(dec: ^Decoder, output: []f32, channels: int, samplerate: int) -> (status: Decode_Status) {
	status = .Complete

	packet: [dynamic]f32
	defer delete(packet)

	frames_wanted := len(output) / channels
	frames_decoded := 0

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

	for (frames_decoded < frames_wanted) && status != .Eof {
		packet_frames_in, packet_frames, eof := _decode_packet(dec, &packet, channels, samplerate)

		if eof {
			status = .Eof
			break
		}

		if packet_frames == 0 {continue}

		overflow_frames := frames_decoded + packet_frames - frames_wanted

		if overflow_frames > 0 {
			copy(output[frames_decoded*channels:], packet[:(packet_frames-overflow_frames)*channels])
			resize(&dec.overflow, overflow_frames * channels)
			copy(dec.overflow[:], packet[(packet_frames-overflow_frames)*channels : packet_frames*channels])
		}
		else {
			copy(output[frames_decoded*channels:], packet[:packet_frames*channels])
		}

		frames_decoded += packet_frames
		dec.frame_index += packet_frames_in

		if dec.frame_index >= dec.frame_count {
			status = .Eof
			break
		}
	}

	return
}

seek :: proc(dec: ^Decoder, second: int) {
	if !dec.is_open {return}
	ffmpeg.seek_to_second(dec.ff, auto_cast second)
	dec.frame_index = second * dec.samplerate
	clear(&dec.overflow)
}

get_second :: proc(dec: Decoder) -> int {
	if !dec.is_open {return 0}

	return (dec.frame_index) / (dec.samplerate)
}

get_duration :: proc(dec: Decoder) -> int {
	if !dec.is_open {return 0}

	return auto_cast dec.duration_seconds
}

load_thumbnail :: proc(filename: string) -> (data: rawptr, w, h: int, ok: bool) {
	filename_buf: [512]u8
	_w, _h: i32

	copy(filename_buf[:511], filename)
	ffmpeg.load_thumbnail(cstring(&filename_buf[0]), &data, &_w, &_h) or_return
	w = auto_cast _w
	h = auto_cast _h

	ok = true
	return
}

delete_thumbnail :: proc(data: rawptr) {
	ffmpeg.free_thumbnail(data);
}

