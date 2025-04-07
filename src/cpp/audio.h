#ifndef AUDIO_H_
#define AUDIO_H_

#include <stdint.h>

typedef void Audio_Callback(float *out_buffer, int32_t frame_count, void *user_data);

struct Audio_Stream_Info {
	int32_t sample_rate;
	int32_t channels;
	// Time between filling the audio buffer and the sound actually
	// coming out the device
	int32_t delay_ms;
	int32_t buffer_duration_ms;
};

extern "C" {
	int32_t audio_run(Audio_Callback *callback, void *callback_data, Audio_Stream_Info *out_info);
	void audio_kill();
	void audio_interrupt();
	void audio_set_volume(float volume);
	float audio_get_volume();
}

#endif
