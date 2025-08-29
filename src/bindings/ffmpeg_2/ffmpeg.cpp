#include "ffmpeg.h"

extern "C" {
#include <libavutil/channel_layout.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
}

struct FFMPEG_Context {
	AVFormatContext *demuxer;
	AVCodecContext *decoder;
	AVCodecParameters *codecpar;
	AVPacket *packet;
	AVFrame *frame;
	uint32_t stream_index;
	AVSampleFormat sample_format;
	Audio_Spec input_spec;
	int64_t current_frame;
	
	SwrContext *resampler;
	// Spec used when creating resampler
	Audio_Spec resampler_spec;

	int32_t samplerate;
};

void ffmpeg_free_context(FFMPEG_Context *ff) {
	if (!ff) return;

	if (ff->frame) {
		av_frame_unref(ff->frame);
		av_frame_free(&ff->frame);
	}

	if (ff->packet) {
		av_packet_unref(ff->packet);
		av_packet_free(&ff->packet);
	}

	delete ff;
}

FFMPEG_Context *ffmpeg_create_context() {
	FFMPEG_Context *ff = new FFMPEG_Context;
	*ff = {};
	ff->packet = av_packet_alloc();
	ff->frame = av_frame_alloc();
	return ff;
}

bool ffmpeg_open_input(FFMPEG_Context *ff, const char *filename, File_Info *info_out) {
	bool found_stream;
	const AVCodec *codec;
	const AVStream *stream;
	const AVCodecParameters *codecpar;
	int64_t duration;

	if (!ff) return false;

	ffmpeg_close_input(ff);

	ff->demuxer = avformat_alloc_context();
	if (avformat_open_input(&ff->demuxer, filename, NULL, NULL)) {
		return false;
	}
	avformat_find_stream_info(ff->demuxer, NULL);

	for (int i = 0; i < ff->demuxer->nb_streams; ++i) {
		if (ff->demuxer->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
			ff->stream_index = i;
			found_stream = true;
			break;
		}
	}

	if (!found_stream) {
		ffmpeg_close_input(ff);
		return false;
	}

	stream = ff->demuxer->streams[ff->stream_index];
	codecpar = stream->codecpar;
	codec = avcodec_find_decoder(codecpar->codec_id);

	if (!codec) {
		ffmpeg_close_input(ff);
		return false;
	}

	ff->decoder = avcodec_alloc_context3(codec);

	if (avcodec_parameters_to_context(ff->decoder, codecpar) < 0) {
		ffmpeg_close_input(ff);
		return false;
	}

	if (avcodec_open2(ff->decoder, codec, NULL)) {
		ffmpeg_close_input(ff);
		return false;
	}

	ff->sample_format = (AVSampleFormat)codecpar->format;
	ff->samplerate = codecpar->sample_rate;
	ff->input_spec.samplerate = codecpar->sample_rate;
	ff->input_spec.channels = codecpar->ch_layout.nb_channels;

	duration = (ff->demuxer->duration / AV_TIME_BASE);
	info_out->spec = ff->input_spec;
	info_out->total_frames = duration * ff->input_spec.samplerate;

	ff->frame = av_frame_alloc();
	ff->packet = av_packet_alloc();

	return true;
}

Decode_Status ffmpeg_decode_packet(FFMPEG_Context *ff, const Audio_Spec &output_spec, Packet *packet_out) {
	Decode_Status status = DecodeStatus_Ok;
	int error;

	if (!ff || !ff->demuxer) {return DecodeStatus_NoFile;}

	packet_out->frames_in = 0;
	packet_out->frames_out = 0;
	for (int i = 0; i < output_spec.channels; ++i) {
		free(packet_out->data[i]);
		packet_out->data[i] = NULL;
	}

	// Read frames until we get one from the desired stream, or error/eof
	while (1) {
		error = av_read_frame(ff->demuxer, ff->packet);
		if (error == AVERROR_EOF) {
			av_packet_unref(ff->packet);
			return DecodeStatus_Eof;
		}
		else if (error < 0) {
			av_packet_unref(ff->packet);
			return DecodeStatus_Error;
		}
		else if (ff->packet->stream_index == ff->stream_index) {
			avcodec_send_packet(ff->decoder, ff->packet);
			break;
		}
		av_packet_unref(ff->packet);
	}
	defer(av_packet_unref(ff->packet));

	// Create resampler if needed
	if (ff->resampler == NULL || ff->resampler_spec != output_spec) {
		AVChannelLayout out_ch_layout;

		if (ff->resampler) {
			swr_free(&ff->resampler);
		}

		out_ch_layout = AV_CHANNEL_LAYOUT_STEREO;

		swr_alloc_set_opts2(&ff->resampler,
			&out_ch_layout, AV_SAMPLE_FMT_FLTP, output_spec.samplerate,
			&ff->decoder->ch_layout, ff->decoder->sample_fmt, ff->decoder->sample_rate,
			0, NULL
		);

		if (!ff->resampler) return DecodeStatus_Error;

		swr_init(ff->resampler);

		ff->resampler_spec = output_spec;
	}

	while (avcodec_receive_frame(ff->decoder, ff->frame) >= 0) {
		const float sample_ratio = (float)output_spec.samplerate / (float)ff->input_spec.samplerate;
		int read_frames = ff->frame->nb_samples;
		int write_frames = (int)floorf((float)read_frames * sample_ratio);
		auto output_offset = packet_out->frames_out;
		uint8_t *output_ptr[AV_NUM_DATA_POINTERS];
		int packet_length = output_offset + write_frames;

		for (int i = 0; i < output_spec.channels; ++i) {
			packet_out->data[i] = (f32*)realloc(packet_out->data[i], packet_length * sizeof(f32));
			output_ptr[i] = (uint8_t*)&packet_out->data[i][output_offset];
		}

		swr_convert(ff->resampler,
			output_ptr, write_frames,
			(const uint8_t**)ff->frame->data, read_frames
		);

		av_frame_unref(ff->frame);

		packet_out->frames_out += write_frames;
		packet_out->frames_in += read_frames;
	}

	return status;
}

bool ffmpeg_seek_to_second(FFMPEG_Context *ff, int64_t second) {
	if (ff->demuxer != NULL) {
		auto base = ff->demuxer->streams[ff->stream_index]->time_base;
		int64_t ts = av_rescale(second, base.den, base.num);
		avformat_seek_file(ff->demuxer, ff->stream_index, 0, ts, ts, 0);
		avcodec_flush_buffers(ff->decoder);
		ff->current_frame = second * ff->samplerate;
		return true;
	}

	return false;
}

void ffmpeg_free_packet(Packet *packet) {
	for (int ch = 0; ch < MAX_AUDIO_CHANNELS; ++ch) {
		if (packet->data[ch]) free(packet->data[ch]);
	}
}

void ffmpeg_close_input(FFMPEG_Context *ff) {
	if (!ff) return;

	if (ff->resampler) {
		swr_free(&ff->resampler);
		ff->resampler = NULL;
	}

	if (ff->frame) {
		av_frame_unref(ff->frame);
		av_frame_free(&ff->frame);
		ff->frame = NULL;
	}

	if (ff->packet) {
		av_packet_unref(ff->packet);
		av_packet_free(&ff->packet);
		ff->packet = NULL;
	}

	if (ff->decoder) {
		avcodec_close(ff->decoder);
		avcodec_free_context(&ff->decoder);
		ff->decoder = NULL;
	}

	if (ff->demuxer) {
		avformat_close_input(&ff->demuxer);
		avformat_free_context(ff->demuxer);
		ff->demuxer = NULL;
	}
}

bool ffmpeg_is_open(FFMPEG_Context *ff) {
	if (!ff) return false;
	return ff->demuxer != NULL;
}

bool ffmpeg_load_thumbnail(const char *filename, void **data, int32_t *w, int32_t *h) {
	AVFormatContext *demuxer;
	AVCodecContext *decoder;
	AVCodecParameters *codecpar;
	const AVCodec *codec;
	AVPacket *pkt = NULL;
	AVFrame *src_frame;
	AVFrame *dst_frame;
	SwsContext *rescaler;
	size_t image_size;

	demuxer = avformat_alloc_context();
	defer(avformat_free_context(demuxer));
	if (avformat_open_input(&demuxer, filename, NULL, NULL)) {
		return false;
	}
	defer(avformat_close_input(&demuxer));

	for (int i = 0; i < demuxer->nb_streams; ++i) {
		AVStream *stream = demuxer->streams[i];
		if (stream->codecpar == NULL) continue;
		if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
			pkt = &stream->attached_pic;
			codecpar = stream->codecpar;
		}
	}

	if (!pkt)
		return false;

	src_frame = av_frame_alloc();
	defer(av_frame_free(&src_frame));

	dst_frame = av_frame_alloc();
	defer(av_frame_free(&dst_frame));

	codec = avcodec_find_decoder(codecpar->codec_id);
	if (codec == NULL)
		return false;
	
	decoder = avcodec_alloc_context3(codec);
	defer(avcodec_free_context(&decoder));
	avcodec_parameters_to_context(decoder, codecpar);
	if (avcodec_open2(decoder, codec, NULL))
		return false;
	defer(avcodec_close(decoder));

	if (avcodec_send_packet(decoder, pkt))
		return false;
	if (avcodec_receive_frame(decoder, src_frame))
		return false;

	rescaler = sws_getContext(
		src_frame->width, src_frame->height, (AVPixelFormat)src_frame->format,
		src_frame->width, src_frame->height, AV_PIX_FMT_RGBA, SWS_BICUBIC, NULL, NULL, NULL
	);

	if (rescaler == NULL)
		return false;
	defer(sws_freeContext(rescaler));

	image_size = src_frame->width * src_frame->height * 4;
	*data = malloc(image_size);
	*w = src_frame->width;
	*h = src_frame->height;

	if (sws_scale_frame(rescaler, dst_frame, src_frame) >= 0) {
		av_image_copy_to_buffer(
			(uint8_t*)*data, image_size,
			dst_frame->data, dst_frame->linesize, AV_PIX_FMT_RGBA,
			dst_frame->width, dst_frame->height, 4
		);
	}
	else {
		free(data);
		*data = NULL;
		return false;
	}

	return true;
}

void ffmpeg_free_thumbnail(void *data) {
	free(data);
}
