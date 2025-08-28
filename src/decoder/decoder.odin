package decoder_v2

import "core:math"
import "core:strings"
import "core:log"

import av "src:bindings/ffmpeg"

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
	demuxer: ^av.FormatContext,
	decoder: ^av.CodecContext,
	packet: ^av.Packet,
	resampler: ^av.SwrContext,
	resampler_channels: int,
	resampler_samplerate: int,
	frame: ^av.Frame,
	stream_index: int,
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
	codec: ^av.Codec
	stream: ^av.Stream
	filename := strings.clone_to_cstring(filename_native)
	defer delete(filename)

	close(dec)

	// Demuxer
	dec.demuxer = av.format_alloc_context()
	if dec.demuxer == nil {return}
	if av.format_open_input(&dec.demuxer, filename, nil, nil) != 0 {return}
	defer if !ok {av.format_close_input(&dec.demuxer); av.format_free_context(dec.demuxer)}

	av.format_find_stream_info(dec.demuxer, nil)
	dec.stream_index = -1
	for i in 0..<dec.demuxer.nb_streams {
		if dec.demuxer.streams[i].codecpar.codec_type == .AUDIO {
			dec.stream_index = auto_cast i
			break
		}
	}
	if dec.stream_index == -1 {return}

	stream = dec.demuxer.streams[dec.stream_index]

	// Decoder
	codecpar := stream.codecpar
	codec = av.codec_find_decoder(codecpar.codec_id)
	dec.decoder = av.codec_alloc_context3(codec)
	av.codec_parameters_to_context(dec.decoder, codecpar)
	av.codec_open2(dec.decoder, codec, nil)

	dec.packet = av.packet_alloc()
	dec.frame = av.frame_alloc()
	dec.samplerate = auto_cast codecpar.sample_rate
	dec.channels = auto_cast codecpar.ch_layout.nb_channels
	dec.frame_index = 0
	dec.duration_seconds = (dec.demuxer.duration / av.TIME_BASE)
	dec.frame_count = int(dec.duration_seconds) * int(codecpar.sample_rate)

	if info != nil {
		info^ = {}
		if codec.name != nil {
			copy(info.codec[:len(info.codec)-1], string(codec.name))
		}
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

	if dec.resampler != nil {
		av.swr_free(&dec.resampler)
		dec.resampler = nil
	}
	if dec.frame != nil {
		av.frame_unref(dec.frame)
		av.frame_free(&dec.frame)
		dec.frame = nil
	}
	if dec.packet != nil {
		av.packet_unref(dec.packet)
		av.packet_free(&dec.packet)
		dec.packet = nil
	}
	if dec.decoder != nil {
		av.codec_close(dec.decoder)
		av.codec_free_context(&dec.decoder)
		dec.decoder = nil
	}
	if dec.demuxer != nil {
		av.format_close_input(&dec.demuxer)
		av.format_free_context(dec.demuxer)
		dec.demuxer = nil
	}
}

is_open :: proc(dec: Decoder) -> bool {
	return dec.is_open
}

@private
_decode_packet :: proc(dec: ^Decoder, output: ^[dynamic]f32, channels, samplerate: int) -> (read: int, written: int, eof: bool) {
	error := av.read_frame(dec.demuxer, dec.packet)
	if error < 0 {
		eof = u32(error) == av.ERROR_EOF
		log.debug("EOF")
		return
	}

	clear(output)

	error = av.codec_send_packet(dec.decoder, dec.packet)
	defer av.packet_unref(dec.packet)

	if int(dec.packet.stream_index) != dec.stream_index {
		return
	}

	if error < 0 {return}
 
	if dec.resampler == nil || dec.resampler_channels != channels || dec.resampler_samplerate != samplerate {
		if dec.resampler != nil {av.swr_free(&dec.resampler)}
		dec.resampler_channels = channels
		dec.resampler_samplerate = samplerate
		out_ch_layout: av.ChannelLayout

		av.channel_layout_default(&out_ch_layout, auto_cast channels)
		av.swr_alloc_set_opts2(
			&dec.resampler, &out_ch_layout, .FLT, auto_cast samplerate,
			&dec.decoder.ch_layout, dec.decoder.sample_fmt, dec.decoder.sample_rate,
			0, nil
		)
		if dec.resampler == nil {return}
		av.swr_init(dec.resampler)
	}

	for av.codec_receive_frame(dec.decoder, dec.frame) >= 0 {
		defer av.frame_unref(dec.frame)

		sample_ratio := f32(samplerate) / f32(dec.frame.sample_rate)
		write_frames := int(math.floor(f32(dec.frame.nb_samples) * sample_ratio))
		read_frames := auto_cast dec.frame.nb_samples

		output_offset := len(output)
		resize(output, output_offset + (write_frames*channels))
		output_ptr := &output[output_offset]

		converted := av.swr_convert(
			dec.resampler,
			auto_cast &output_ptr, auto_cast write_frames,
			auto_cast &dec.frame.data[0], read_frames
		)

		if converted < 0 {
			log.error("swr_convert returned", converted)
			continue
		}

		written += auto_cast write_frames
		read += auto_cast dec.frame.nb_samples
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
	dec.frame_index = second * dec.samplerate
	base := dec.demuxer.streams[dec.stream_index].time_base
	ts := av.rescale(auto_cast second, auto_cast base.den, auto_cast base.num)
	av.format_seek_file(dec.demuxer, auto_cast dec.stream_index, 0, ts, ts, 0)
	av.codec_flush_buffers(dec.decoder)
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

load_thumbnail :: proc(dec: Decoder) -> (data: rawptr, w, h: int, ok: bool) {
	pkt: ^av.Packet
	codec: ^av.Codec
	decoder: ^av.CodecContext
	codecpar: ^av.CodecParameters
	frame: ^av.Frame

	for stream in dec.demuxer.streams[:dec.demuxer.nb_streams] {
		if stream.codecpar == nil {continue}
		if stream.codecpar.codec_type == av.MediaType.VIDEO {
			pkt = stream.attached_pic
			codecpar = stream.codecpar
			break
		}
	}

	if pkt == nil {return}

	frame = av.frame_alloc()
	defer av.frame_free(&frame)

	codec = av.codec_find_decoder(codecpar.codec_id)
	if codec == nil {return}

	decoder = av.codec_alloc_context3(codec)
	defer av.codec_free_context(&decoder)

	if av.codec_open2(decoder, codec, nil) != 0 {return}
	defer av.codec_close(decoder)

	if av.codec_send_packet(decoder, pkt) != 0 {return}
	if av.codec_receive_frame(decoder, frame) != 0 {return}

	w = auto_cast frame.width
	h = auto_cast frame.height

	return
}

