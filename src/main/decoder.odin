package main

import "core:strings"

import "src:bindings/ffmpeg"

Decode_Status :: enum {
	NoFile,
	Complete,
	Eof,
}

Audio_File_Info :: struct {
	codec: [64]u8,
	format_name: [64]u8,
	samplerate: int,
	channels: int,
	duration: int,
}

Decoder :: struct {
	ff: ^ffmpeg.Context,
	overflow: [AUDIO_MAX_CHANNELS][dynamic]f32,
	overflow_samplerate: int,
	overflow_channels: int,
	samplerate: int,
	channels: int,
	frame_index: int,
	frame_count: int,
	duration_seconds: i64,
	is_open: bool,
}

decoder_open :: proc(dec: ^Decoder, filename_native: string, info: ^Audio_File_Info) -> (ok: bool) {
	filename := strings.clone_to_cstring(filename_native)
	defer delete(filename)
	file_info: ffmpeg.File_Info

	decoder_close(dec)

	if dec.ff == nil {
		dec.ff = ffmpeg.create_context()
	}

	ffmpeg.open_input(dec.ff, filename, &file_info) or_return

	dec.samplerate = auto_cast file_info.spec.samplerate
	dec.channels = auto_cast file_info.spec.channels
	dec.frame_index = 0
	dec.duration_seconds = file_info.total_frames / auto_cast file_info.spec.samplerate
	dec.frame_count = auto_cast file_info.total_frames

	if info != nil {
		info^ = {}
		copy(info.codec[:len(info.codec)-1], string(cstring(&file_info.codec_name[0])))
		copy(info.format_name[:len(info.format_name)-1], string(cstring(&file_info.format_name[0])))
		info.samplerate = dec.samplerate
		info.channels = dec.channels
		info.duration = auto_cast dec.duration_seconds
	}
	
	dec.is_open = true
	ok = true
	return
}

decoder_close :: proc(dec: ^Decoder) {
	dec.is_open = false
	dec.frame_index = 0
	dec.frame_count = 0

	for &ch in dec.overflow {
		delete(ch)
		ch = nil
	}

	ffmpeg.close_input(dec.ff)
}

decoder_is_open :: proc(dec: Decoder) -> bool {
	return dec.is_open
}

@(private="file")
_decode_packet :: proc(dec: ^Decoder, output: [][dynamic]f32, samplerate: int) -> (read: int, written: int, eof: bool) {
	pkt: ffmpeg.Packet
	spec: ffmpeg.Audio_Spec
	channels := len(output)
	spec.channels = auto_cast channels
	spec.samplerate = auto_cast samplerate

	if ffmpeg.decode_packet(dec.ff, &spec, &pkt) == .Eof {
		eof = true
		return
	}

	defer ffmpeg.free_packet(&pkt)

	read = auto_cast pkt.frames_in
	written = auto_cast pkt.frames_out

	//resize(output, pkt.frames_out * auto_cast channels)

	/*for frame in 0..<int(pkt.frames_out) {
		for ch in 0..<channels {
			output[(frame*channels) + ch] = pkt.data[ch][frame]
		}
	}*/

	for ch in 0..<channels {
		resize(&output[ch], pkt.frames_out)
		copy(output[ch][:], pkt.data[ch][:pkt.frames_out])
	}

	return
}

decoder_fill_buffer :: proc(dec: ^Decoder, output: [][]f32, samplerate: int) -> (status: Decode_Status) {
	status = .Complete
	channels := len(output)

	if !decoder_is_open(dec^) do return .NoFile

	packet: [AUDIO_MAX_CHANNELS][dynamic]f32
	defer for ch in 0..<channels do delete(packet[ch])

	frames_wanted := len(output[0])
	frames_decoded := 0

	if len(dec.overflow) > 0 {
		overflow_frames := len(dec.overflow[0])
		frames_to_copy := min(overflow_frames, len(output[0]))

		for ch in 0..<channels {
			copy(output[ch], dec.overflow[ch][:frames_to_copy])
		}
		
		if overflow_frames < frames_wanted {
			for ch in 0..<channels do remove_range(&dec.overflow[ch], 0, overflow_frames)
		}
		else {
			for ch in 0..<channels do clear(&dec.overflow[ch])
		}
		
		frames_decoded += overflow_frames
	}

	for (frames_decoded < frames_wanted) && status != .Eof {
		packet_frames_in, packet_frames, eof := _decode_packet(dec, packet[:channels], samplerate)

		if eof {
			status = .Eof
			break
		}

		if packet_frames == 0 {continue}

		overflow_frames := frames_decoded + packet_frames - frames_wanted

		if overflow_frames > 0 {
			for ch in 0..<channels {
				copy(output[ch][frames_decoded:], packet[ch][:(packet_frames-overflow_frames)])
				resize(&dec.overflow[ch], overflow_frames)
				copy(dec.overflow[ch][:], packet[ch][(packet_frames-overflow_frames): packet_frames])
			}
		}
		else {
			for ch in 0..<channels {
				copy(output[ch][frames_decoded:], packet[ch][:packet_frames])
			}
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

decoder_seek :: proc(dec: ^Decoder, second: int) {
	if !dec.is_open {return}
	ffmpeg.seek_to_second(dec.ff, auto_cast second)
	dec.frame_index = second * dec.samplerate
	for ch in 0..<dec.channels do clear(&dec.overflow[ch])
}

decoder_get_second :: proc(dec: Decoder) -> int {
	if !dec.is_open {return 0}

	return (dec.frame_index) / (dec.samplerate)
}

decoder_get_duration :: proc(dec: Decoder) -> int {
	if !dec.is_open {return 0}

	return auto_cast dec.duration_seconds
}
