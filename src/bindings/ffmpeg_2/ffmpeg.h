#include "common.h"

#define MAX_AUDIO_CHANNELS 2

enum Decode_Status {
	DecodeStatus_Ok,
	DecodeStatus_Eof,
	DecodeStatus_NoFile,
	DecodeStatus_Error,
};

struct Audio_Spec {
	int32_t channels;
	int32_t samplerate;

	inline bool operator!=(const Audio_Spec& other) {
		return channels != other.channels || samplerate != other.samplerate;
	}
};

struct File_Info {
	Audio_Spec spec;
	int64_t total_frames;
};

struct Packet {
	int32_t frames_in;
	int32_t frames_out;
	f32 *data[MAX_AUDIO_CHANNELS];
};

struct FFMPEG_Context;

extern "C" {
FFMPEG_Context *ffmpeg_create_context();
void ffmpeg_free_context(FFMPEG_Context *ff);
bool ffmpeg_open_input(FFMPEG_Context *ff, const char *filename, File_Info *info_out);
void ffmpeg_close_input(FFMPEG_Context *ff);
bool ffmpeg_is_open(FFMPEG_Context *ff);
Decode_Status ffmpeg_decode_packet(FFMPEG_Context *ff, const Audio_Spec &output_spec, Packet *packet_out);
bool ffmpeg_load_thumbnail(const char *filename, void **data, int32_t *w, int32_t *h);
void ffmpeg_free_thumbnail(void *data);
}
