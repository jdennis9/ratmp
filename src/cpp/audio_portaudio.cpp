#ifdef __linux__
#include <portaudio.h>
#include <stdio.h>
#include "audio.h"

static struct {
	Audio_Callback *callback;
	void *callback_data;
	PaStream *stream;
	float volume;
	int channels;
} g;


static int callback_wrapper(
	const void *input,
	void *output,
    unsigned long frames,
    const PaStreamCallbackTimeInfo* time_info,
    PaStreamCallbackFlags status,
    void *userData)
{
	float *output_samples = (float*)output;
	g.callback((float*)output, frames, g.callback_data);

	for (int i = 0; i < frames * g.channels; ++i) {
		output_samples[i] *= g.volume;
	}

    return 0;
}


int32_t audio_run(Audio_Callback *cb, void *cb_data, Audio_Stream_Info *info) {
	PaError error;

	Pa_Initialize();
	info->channels = 2;
	info->sample_rate = 44100;
	g.callback = cb;
	g.callback_data = cb_data;
	g.channels = 2;
	g.volume = 1.f;

	error = Pa_OpenDefaultStream(&g.stream, 0, g.channels, paFloat32, 44100, 0, &callback_wrapper, cb_data);

	if (error) {
		printf("[audio] Failed to initialize PortAudio stream with error code %d (%s)\n", error, Pa_GetErrorText(error));
		return 0;
	}

	printf("[audio] Pa_StartStream\n");
	Pa_StartStream(g.stream);

	return 1;
}

void audio_kill() {
	Pa_StopStream(g.stream);
	Pa_CloseStream(g.stream);
	Pa_Terminate();
}

void audio_interrupt() {
}

void audio_set_volume(float volume) {
	g.volume = volume;
}

float audio_get_volume() {
	return g.volume;
}
#endif
