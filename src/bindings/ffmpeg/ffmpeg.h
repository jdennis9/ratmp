#include "../common.h"

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

struct Replay_Gain {
	float track_gain;
	float album_gain;
	float track_peak;
	float album_peak;
};

struct File_Info {
	char codec_name[64];
	char format_name[64];
	Audio_Spec spec;
	int64_t total_frames;
	bool has_replay_gain;
	Replay_Gain replay_gain;
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
bool ffmpeg_probe_codec_and_format(const char *filename, char *codec, char *format, int buf_size);
bool ffmpeg_is_open(FFMPEG_Context *ff);
Decode_Status ffmpeg_decode_packet(FFMPEG_Context *ff, const Audio_Spec &output_spec, Packet *packet_out);
void ffmpeg_free_packet(Packet *packet);
bool ffmpeg_seek_to_second(FFMPEG_Context *ff, int64_t second);
}
