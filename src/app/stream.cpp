/*
   Copyright 2024 Jamie Dennis

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
#define WIN32_LEAN_AND_MEAN
#include "stream.h"
#include "files.h"
#include "util/auto_array_impl.h"
#include "util.h"
#include "main.h"
#include <ctype.h>
#include <Windows.h>
#include <mutex>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
}

struct Decoder {
	AVFormatContext *demuxer;
	AVCodecContext *decoder;
	AVPacket *packet;
	SwrContext *resampler;
	AVFrame *frame;
	AVFrame *thumbnail_frame;
	AVPacket *thumbnail_packet;
	int32 stream_index;
	int32 thumbnail_stream_index;
	uint8 *overflow[AV_NUM_DATA_POINTERS];
	uint32 overflow_frame_count;
	Audio_Client_Stream *output_stream;
	uint32 sample_rate;
	int64 current_sample;
	int64 total_samples;
	SRWLOCK lock;
	bool is_open;
};

struct Waveform_Image_Load {
	char path[512];
};

static struct {
	Audio_Client client;
	Stream_State state;
	Decoder decoder;
	float volume;
	Image waveform_image;
	HANDLE waveform_loader_thread;
	bool cancel_waveform_load;
} G;

//==========================================================================
// Internal functions
//==========================================================================

static void stream_callback(void *data, uint32 frame_count, uint8 *buffers[]);
static void get_buffers_with_offset(Decoder *dec, uint8 *in[], uint8 *out[], AVSampleFormat sample_format, uint32 frame_index);
static void zero_buffers(Decoder *dec, uint32 frame_count, uint8 *buffers[]);
static DWORD generate_waveform_image(LPVOID data_ptr);

// Closes the current file. Does not undo intialisation
static void close_decoder(Decoder *dec);
static bool decoder_load(Decoder *dec, const char *filename, bool no_audio = false);
static void decoder_lock(Decoder *dec);
static void decoder_unlock(Decoder *dec);
static int64 decoder_get_pos(Decoder *dec);
static int64 decoder_get_duration(Decoder *dec);
static void decoder_seek(Decoder *dec, int64 millisecond);

static void zero_buffers(Decoder *dec, uint32 frame_count, uint8 *buffers[]) {
	Audio_Stream_Spec *spec = &dec->output_stream->spec;
	if (av_sample_fmt_is_planar(spec->sample_format)) {
		uint32 buffer_size = frame_count * av_get_bytes_per_sample(spec->sample_format);
		for (uint32 i = 0; i < spec->channel_count; ++i) {
			memset(buffers[i], 0, buffer_size);
		}
	}
	else {
		uint32 buffer_size = frame_count * spec->channel_count * av_get_bytes_per_sample(spec->sample_format);
		memset(buffers[0], 0, buffer_size);
	}
}

static void get_buffers_with_offset(Decoder *dec, uint8 *in[], uint8 *out[], AVSampleFormat sample_format, uint32 frame_index) {
	const uint32 sample_size = av_get_bytes_per_sample(sample_format);
	if (av_sample_fmt_is_planar(sample_format)) {
		for (uint32 i = 0; i < dec->output_stream->spec.channel_count; ++i) 
			out[i] = in[i] + (frame_index * sample_size);
	}
	else {
		out[0] = in[0] + (sample_size * frame_index * dec->output_stream->spec.channel_count);
	}
}

static void decoder_lock(Decoder *dec) {
	AcquireSRWLockExclusive(&dec->lock);
}

static void decoder_unlock(Decoder *dec) {
	ReleaseSRWLockExclusive(&dec->lock);
}

static int64 decoder_get_pos(Decoder *dec) {
	int64 pos;

	if (!dec->is_open) pos = 0;
	else pos = (dec->current_sample*1000) / (dec->sample_rate);

	return pos;
}

static int64 decoder_get_duration(Decoder *dec) {
	int64 duration;

	if (!dec->is_open) duration = 0;
	else {
		auto base = dec->demuxer->streams[dec->stream_index]->time_base;
		duration = (dec->demuxer->duration / AV_TIME_BASE) * 1000;
	}

	return duration;
}

static void decoder_seek(Decoder *dec, int64 millisecond) {
	if (dec->is_open) {
		int64 second = millisecond / 1000;
		dec->current_sample = second * dec->sample_rate;
		auto base = dec->demuxer->streams[dec->stream_index]->time_base;
		int64 ts = av_rescale(second, base.den, base.num);
		avformat_seek_file(dec->demuxer, dec->stream_index, 0, ts, ts, 0);
		avcodec_flush_buffers(dec->decoder);
		dec->overflow_frame_count = 0;
		dec->output_stream->interrupt();
	}
}

static void close_decoder(Decoder *dec) {
	if (dec->is_open) {
		for (uint32 i = 0; i < ARRAY_LENGTH(dec->overflow); ++i) {
			free(dec->overflow[i]);
		}
					
		if (dec->thumbnail_frame) {
			av_frame_unref(dec->thumbnail_frame);
			av_frame_free(&dec->thumbnail_frame);
			av_packet_free(&dec->thumbnail_packet);
		}
		
		if (dec->frame) {
			av_frame_unref(dec->frame);
			av_frame_free(&dec->frame);
		}
		
		if (dec->packet) {
			av_packet_unref(dec->packet);
			av_packet_free(&dec->packet);
		}
		
		avformat_close_input(&dec->demuxer);
		avformat_free_context(dec->demuxer);
		if (dec->decoder) {
			avcodec_close(dec->decoder);
			avcodec_free_context(&dec->decoder);
			swr_free(&dec->resampler);
		}
		dec->demuxer = NULL;
		dec->decoder = NULL;
		dec->thumbnail_packet = NULL;
		dec->current_sample = 0;
		dec->overflow_frame_count = 0;
		dec->total_samples = 0;
		dec->is_open = false;
	}
}

static inline float lerp(float from, float to, float factor) {
	return from + (factor * (to - from));
}

// return true on eof
static bool decoder_decode(Decoder *dec, uint8 *buffers[], uint32 frame_count) {
	Audio_Stream_Spec *spec = &dec->output_stream->spec;
	const uint32 out_sample_size = av_get_bytes_per_sample(spec->sample_format);
	uint32 frames_written = 0;
	AVChannelLayout channel_layout = {};
	bool eof = false;
	
	if (dec->overflow_frame_count) {
		if (av_sample_fmt_is_planar(spec->sample_format)) {
			for (uint32 i = 0; i < spec->channel_count; ++i)
				memcpy(buffers[i], dec->overflow[i], out_sample_size * dec->overflow_frame_count);
		}
		else {
			memcpy(buffers[0], dec->overflow[0], out_sample_size * dec->overflow_frame_count * spec->channel_count);
		}
		frames_written += dec->overflow_frame_count;
		dec->overflow_frame_count = 0;
	}
	
	while (frames_written < frame_count) {
		int error;
		error = av_read_frame(dec->demuxer, dec->packet);
		if (error < 0) {
			if (error != AVERROR_EOF) {
				char error_message[256];
				av_strerror(error, error_message, 256);
				log_debug("AVERROR: %s\n", error_message);
			}
			
			eof = error == AVERROR_EOF;
			break;
		}
		avcodec_send_packet(dec->decoder, dec->packet);
		
		if (dec->packet->stream_index == dec->stream_index) {
			while (avcodec_receive_frame(dec->decoder, dec->frame) >= 0) {
				uint8 *out_buffers[AV_NUM_DATA_POINTERS];
				const uint32 in_sample_size = av_get_bytes_per_sample((AVSampleFormat)dec->frame->format);
				float sample_ratio = (float)spec->sample_rate/(float)dec->frame->sample_rate;
				int write_frames = (int)floorf(dec->frame->nb_samples * sample_ratio);
				int read_frames = dec->frame->nb_samples;
				int write_overflow_frames = 0;
				int read_overflow_frames = 0;
				int converted = 0;
				
				if ((write_frames + frames_written) >= frame_count) {
					write_overflow_frames = (write_frames + frames_written) - frame_count;
					read_overflow_frames = (int)ceilf(write_overflow_frames / sample_ratio);
					write_frames -= write_overflow_frames;
					read_frames -= read_overflow_frames;
				}
				
				get_buffers_with_offset(dec, (uint8 **)buffers, out_buffers, spec->sample_format, frames_written);
				converted = swr_convert(dec->resampler, out_buffers, write_frames, 
										(const uint8**)dec->frame->data, read_frames);
				frames_written += write_frames;
				if (write_overflow_frames) {
					uint8 *in_buffers[AV_NUM_DATA_POINTERS] = {};
					get_buffers_with_offset(dec, dec->frame->data, in_buffers, (AVSampleFormat)dec->frame->format, read_frames);
					converted = swr_convert(dec->resampler, (uint8 **)dec->overflow, write_overflow_frames,
											(const uint8 **)in_buffers, read_overflow_frames);
					dec->overflow_frame_count = write_overflow_frames;
					frames_written += write_overflow_frames;
				}
				
				dec->current_sample += dec->frame->nb_samples;
				av_frame_unref(dec->frame);
			}
		}
		
		av_packet_unref(dec->packet);
	}
	
	return eof;
}

static void stream_callback(void *data, uint32 frame_count, uint8 *buffers[]) {
	Decoder *dec = (Decoder *)data;
	decoder_lock(dec);
	
	if (!dec->is_open || G.state == STREAM_STATE_STOPPED || G.state == STREAM_STATE_PAUSED) {
		zero_buffers(dec, frame_count, buffers);
		decoder_unlock(dec);
		return;
	}
	
	bool eof = decoder_decode(dec, buffers, frame_count);
	
	int64 duration = decoder_get_duration(dec);
	int64 position = decoder_get_pos(dec);

	decoder_unlock(dec);
	
	if (eof) {
		post_event(EVENT_STREAM_END_OF_TRACK, 0, 0);
	}

	return;
}

static bool decoder_get_thumbnail(Decoder *dec, int size, Image *out) {
	if (!dec->demuxer || (dec->thumbnail_stream_index == -1)) {
		log_debug("No thumbnail for decoder %p\n", dec);
		return false;
	}
	AVPacket *pkt = &dec->demuxer->streams[dec->thumbnail_stream_index]->attached_pic;

	if (pkt) {
		if (!dec->thumbnail_frame) {
			const AVCodec *codec;
			AVCodecContext *decoder;
			AVCodecParameters *codecpar = dec->demuxer->streams[dec->thumbnail_stream_index]->codecpar;
			AVFrame *image;

			image = av_frame_alloc();
			defer(av_frame_free(&image));
			dec->thumbnail_frame = av_frame_alloc();
			defer(av_frame_free(&dec->thumbnail_frame));
			codec = avcodec_find_decoder(codecpar->codec_id);

			if (!codec) {
				return false;
			}

			decoder = avcodec_alloc_context3(codec);
			defer(avcodec_free_context(&decoder));
			avcodec_parameters_to_context(decoder, codecpar);
			if (avcodec_open2(decoder, codec, NULL)) {
				return false;
			}
			defer(avcodec_close(decoder));

			if (avcodec_send_packet(decoder, pkt)) return false;
			if (avcodec_receive_frame(decoder, image)) return false;

			SwsContext *rescaler = sws_getContext(
				image->width,
				image->height,
				(AVPixelFormat)image->format,
				size,
				size,
				AV_PIX_FMT_RGBA,
				SWS_BICUBIC,
				NULL,
				NULL,
				NULL);
			
			if (!rescaler) return false;
			defer(sws_freeContext(rescaler));
			
			sws_scale_frame(rescaler, dec->thumbnail_frame, image);
			av_packet_unref(pkt);

			AVFrame *th = dec->thumbnail_frame;

			out->data = malloc(th->width * th->height * 4);
			out->width = th->width;
			out->height = th->height;

			av_image_copy_to_buffer((uint8 *)out->data, th->width * th->height * 4,
				th->data,
				th->linesize,
				AV_PIX_FMT_RGBA,
				th->width,
				th->height,
				4);
			
			log_debug("Loaded thumbnail for %p\n", dec);
			return true;
		}
	}

	return false;
}

bool stream_extract_thumbnail(const char *filename, int requested_size, Image *out) {
	Decoder dec = {};
	decoder_load(&dec, filename, true);
	bool ret = decoder_get_thumbnail(&dec, requested_size, out);
	close_decoder(&dec);
	return ret;
}

bool stream_get_thumbnail(Image *out) {
	Decoder *dec = &G.decoder;
	decoder_lock(dec);
	bool ret = decoder_get_thumbnail(dec, g_config.thumbnail_size, out);
	decoder_unlock(dec);
	return ret;
}

void stream_free_thumbnail(Image *image) {
	free(image->data);
}

void stream_get_waveform(Image *image) {
	*image = G.waveform_image;
}

bool stream_open(Audio_Client_ID client_id, const char *preferred_device) {
	get_audio_client(client_id, &G.client);
	av_log_set_level(AV_LOG_QUIET);
	G.client.init();

	USER_ASSERT_FATAL(G.client.get_device_count() > 0, "No audio devices found");

	G.decoder.output_stream = G.client.open_device(0, &stream_callback, &G.decoder);
	G.state = STREAM_STATE_STOPPED;
	G.volume = 1.f;
	
	return true;
}

void stream_set_volume(float volume) {
	G.volume = volume;
	Decoder *dec = &G.decoder;
	decoder_lock(dec);
	dec->output_stream->set_volume(volume);
	decoder_unlock(dec);
}

float stream_get_volume() { 
	return G.volume; 
}

#define IS_EXTENSION(str, ext) (*(uint32*)(str) == *(uint32*)(ext))

bool stream_file_is_supported(const char *file_path) {
	const char *extension_ptr = get_file_extension(file_path);
	char extension[8] = {};
	strncpy(extension, extension_ptr, 7);

	for (int i = 0; i < 8 && extension[i]; ++i) {
		extension[i] = tolower(extension[i]);
	}
	
	bool supported = 
		IS_EXTENSION(extension, "m4a") || IS_EXTENSION(extension, "mp3") || IS_EXTENSION(extension, "wav") ||
		IS_EXTENSION(extension, "aiff") || IS_EXTENSION(extension, "opus") || IS_EXTENSION(extension, "flac") ||
		IS_EXTENSION(extension, "ogg") || IS_EXTENSION(extension, "wma");

	if (!supported) {
		log_debug("File type \"%s\" not supported\n", extension);
	}

	return supported;
}

static bool decoder_load(Decoder *dec, const char *file_path, bool no_audio) {
	const AVCodec *codec;
	const AVStream *stream;
	Audio_Stream_Spec *spec = &dec->output_stream->spec;
	
	decoder_lock(dec);
	defer(decoder_unlock(dec));
	close_decoder(dec);
	
	//================================================================
	// Demuxer
	//================================================================
	dec->demuxer = avformat_alloc_context();
	if (avformat_open_input(&dec->demuxer, file_path, NULL, NULL)) {
		return false;
	}
	avformat_find_stream_info(dec->demuxer, NULL);
	
	dec->stream_index = -1;
	dec->thumbnail_stream_index = -1;
	for (uint32 i = 0; i < dec->demuxer->nb_streams; ++i) {
		if (dec->demuxer->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) dec->stream_index = i;
		else if (dec->demuxer->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) dec->thumbnail_stream_index = i;
	}
	
	if (dec->stream_index == -1) {
		avformat_close_input(&dec->demuxer);
		avformat_free_context(dec->demuxer);
		return false;
	}
	
	stream = dec->demuxer->streams[dec->stream_index];
	
	if (no_audio) {
		dec->is_open = true;
		return true;
	}
	
	//================================================================
	// Decoder
	//================================================================
	
	AVCodecParameters *codecpar = stream->codecpar;
	codec = avcodec_find_decoder(codecpar->codec_id);
	dec->decoder = avcodec_alloc_context3(codec);
	avcodec_parameters_to_context(dec->decoder, codecpar);
	avcodec_open2(dec->decoder, codec, NULL);
	
	av_dump_format(dec->demuxer, dec->stream_index, file_path, false);
	
	dec->packet = av_packet_alloc();
	dec->frame = av_frame_alloc();
	dec->sample_rate = codecpar->sample_rate;
	dec->current_sample = 0;
	
	//================================================================
	// Overflow
	//================================================================
	const uint32 sample_size = av_get_bytes_per_sample(spec->sample_format);
	memset(dec->overflow, 0, sizeof(void*) * ARRAY_LENGTH(dec->overflow));
	dec->overflow_frame_count = 0;
	
	if (av_sample_fmt_is_planar((AVSampleFormat)spec->sample_format)) {
		for (int i = 0; i < codecpar->ch_layout.nb_channels; ++i) {
			dec->overflow[i] = (uint8*)malloc(sample_size * codecpar->sample_rate);
		}
	}
	else {
		dec->overflow[0] = (uint8*)malloc(sample_size * codecpar->sample_rate * codecpar->ch_layout.nb_channels);
	}
	
	//================================================================
	// Resampler
	//================================================================
	AVChannelLayout channel_layout;
	av_channel_layout_default(&channel_layout, spec->channel_count);
	swr_alloc_set_opts2(&dec->resampler, &channel_layout, spec->sample_format, spec->sample_rate,
						&codecpar->ch_layout, (AVSampleFormat)codecpar->format, codecpar->sample_rate, 0, NULL);
	if (!swr_is_initialized(dec->resampler)) swr_init(dec->resampler);
	
	dec->is_open = true;
	dec->output_stream->interrupt();
	
	return true;
}

bool stream_load(const char *file_path) {
	Decoder *dec = &G.decoder;
	if (decoder_load(dec, file_path)) {
		Waveform_Image_Load *waveform = new Waveform_Image_Load;
		strncpy(waveform->path, file_path, sizeof(waveform->path)-1);
		
		// Asynchronously generate the waveform image
		if (G.waveform_loader_thread) {
			G.cancel_waveform_load = true;
			WaitForSingleObject(G.waveform_loader_thread, INFINITE);
			CloseHandle(G.waveform_loader_thread);
		}
		G.cancel_waveform_load = false;
		G.waveform_loader_thread = CreateThread(NULL, 256<<10, &generate_waveform_image, waveform, 0, NULL);
		
		post_event(EVENT_STREAM_THUMBNAIL_READY, 0, 0);
		post_event(EVENT_STREAM_TRACK_LOADED, 0, 0);
		G.state = STREAM_STATE_PLAYING;
		return true;
	}
	
	post_event(EVENT_STREAM_TRACK_LOAD_FAILED, 0, 0);
	G.state = STREAM_STATE_STOPPED;
	return false;
}

Stream_State stream_get_state() { return G.state; }

int64 stream_get_pos() {
	Decoder *dec = &G.decoder;
	decoder_lock(dec);
	int64 pos = decoder_get_pos(dec) / 1000;
	decoder_unlock(dec);
	return pos;
}

int64 stream_get_duration() {
	Decoder *dec = &G.decoder;
	decoder_lock(dec);
	int64 duration = decoder_get_duration(&G.decoder) / 1000;
	decoder_unlock(dec);
	return duration;
}

void stream_seek(int64 second) {
	Decoder *dec = &G.decoder;
	decoder_lock(dec);
	decoder_seek(dec, second);
	decoder_unlock(dec);
}

void stream_toggle_playing() {
	if (G.state == STREAM_STATE_PAUSED) {
		G.state = STREAM_STATE_PLAYING;
		G.decoder.output_stream->interrupt();
	}
	else if (G.state == STREAM_STATE_PLAYING) {
		G.state = STREAM_STATE_PAUSED;
		G.decoder.output_stream->interrupt();
	}
}

void stream_close() {
	G.client.destroy();
}

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>

static float clamp(float x, float min, float max) {
	if (x < min) return min;
	if (x > max) return max;
	return x;
}

//@TODO: Handle super short and super long audio files
static DWORD generate_waveform_image(LPVOID data_ptr) {
	Decoder dec = {};
	Waveform_Image_Load *data = (Waveform_Image_Load*)data_ptr;
	defer(delete data);

	float segment_values[1024];
	Image *image = &G.waveform_image;
	if (image->data) free(image->data);
	image->width = WAVEFORM_IMAGE_HEIGHT;
	image->height = 1024;
	image->data = malloc(image->width*image->height*4);
	memset(image->data, 0, image->width*image->height*4);
	
	const int32 half_width = image->width/2;
	
	// Open the stream and file
	Audio_Memory_Stream *output_stream = new Audio_Memory_Stream(44100);
	defer(output_stream->close());
	defer(delete output_stream);
	dec.output_stream = output_stream;
	if (!decoder_load(&dec, data->path)) {
		log_error("generate_waveform_image(): Could not open file for reading\n");
		delete output_stream;
		delete data;
		return 0;
	}

	defer(close_decoder(&dec));
	
	// Samples per line of the image
	const uint32 samples_per_segment = (decoder_get_duration(&dec) * 44.1)/image->height;
	output_stream->allocate_buffers(samples_per_segment);
	
	int seg_count = 0;
	float segment_sum = 0.f;
	float max_peak = 0.f;

	while (!decoder_decode(&dec,(uint8**)output_stream->buffers, samples_per_segment) && (seg_count < image->height)) {
		float *in = output_stream->buffers[0];
		float sum = 0.f;
		uint32 peak_count = 0;
		uint32 *line = (uint32*)((uint8*)image->data + (image->width * seg_count * 4));
		
		for (uint32 i = 1; i < samples_per_segment-1; ++i) {
			// Check if this sample is a peak
			float a = fabsf(in[i-1]);
			float b = fabsf(in[i]);
			float c = fabsf(in[i+1]);
			
			// If the sample is a peak add it to the peak average
			if ((a < b) && (b > c)) {
				sum += clamp(b, 0.f, 1.f);
				peak_count++;
			}
		}
		
		float avg = sum / (float)peak_count;
		if (isnan(avg)) avg = 0.f;
		avg = clamp(avg, 0.f, 1.f);
		max_peak = MAX(max_peak, avg);
		
		segment_values[seg_count++] = avg;
		segment_sum += avg;
		
		if (G.cancel_waveform_load) break;
	}

	float line_factor = 1.f/max_peak;
	//float line_factor = 1.f;

	if (G.cancel_waveform_load) return 0;
	
	// Fill in unfilled segments with silence
	for (int i = seg_count; i < image->height; ++i) {
		uint32 *line = (uint32*)((uint8*)image->data + (image->width * i * 4));
		line[half_width] = UINT32_MAX;
	}
	
	if (G.cancel_waveform_load) return 0;
	
	for (int seg = 0; seg < seg_count; ++seg) {
		uint32 *line = (uint32*)((uint8*)image->data + (image->width * seg * 4));
		line[half_width] = UINT32_MAX;
		
		int32 wave_height = half_width*segment_values[seg]*line_factor;
		if (wave_height > half_width) wave_height = half_width;
		
		for (int32 i = 0; i < wave_height; ++i) {
			line[(half_width) + i] = UINT32_MAX;
			line[(half_width) - i] = UINT32_MAX;
		}
	}
	
	if (G.cancel_waveform_load) return 0;
	
	post_event(EVENT_STREAM_WAVEFORM_READY, 0, 0);
	
	return 0;
}
