#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <atlbase.h>
#include <stdio.h>
#include <stdint.h>
#include "audio.h"

typedef uint32_t u32;
typedef uint8_t u8;
typedef int16_t s16;
typedef int8_t s8;

#define SAFE_RELEASE(obj) if (obj) { (obj)->Release(); (obj) = nullptr; }

enum {
	SAMPLE_FORMAT_S16,
	SAMPLE_FORMAT_S8,
	SAMPLE_FORMAT_F32,
};

static struct {
	IMMDeviceEnumerator *device_enumerator;
	ISimpleAudioVolume *volume_controller;
	//WAVEFORMATEX *mix_format;
	int sample_format;

	HANDLE lock;
	HANDLE thread;
	HANDLE interrupt_sem;
	HANDLE ready_sem;

	Audio_Callback *callback;
	void *callback_data;
	int sample_rate;
	int channels;
	bool want_kill;
} g;

static void fill_buffer(void *output, int frames) {
	int sample_format;

	if (g.sample_format != SAMPLE_FORMAT_F32) {
		float *buffer = new float[frames * g.channels];
		g.callback(buffer, frames, g.callback_data);
		
		// @TestMe
		switch (g.sample_format) {
			case SAMPLE_FORMAT_S8: {
				s8 *words = (s8*)output;
				for (int i = 0; i < frames; ++i) {
					words[i] = (s8)(buffer[i] * (float)INT8_MAX);
				}
				break;
			}
			case SAMPLE_FORMAT_S16: {
				s16 *words = (s16*)output;
				for (int i = 0; i < frames; ++i) {
					words[i] = (s16)(buffer[i] * (float)INT16_MAX);
				}
				break;
			}
		}
	}
	else {
		g.callback((float*)output, frames, g.callback_data);
	}
}

static DWORD audio_thread_proc(LPVOID user_data) {
	WAVEFORMATEX *format;
	u32 buffer_frame_count;
	IMMDevice *device;
	IAudioClient *audio_client;
	IAudioRenderClient *render_client;
	u8 *buffer;
	DWORD buffer_duration_ms;
	int sample_rate, channels;

	(void)CoInitialize(NULL);

	{
		Audio_Stream_Info *info = (Audio_Stream_Info*)user_data;

		g.device_enumerator->GetDefaultAudioEndpoint(EDataFlow::eRender, ERole::eConsole, &device);
		device->Activate(__uuidof(audio_client), CLSCTX_ALL, NULL, (void **)&audio_client);
		audio_client->GetMixFormat(&format);

		if (format->wFormatTag == WAVE_FORMAT_PCM) {
			// @TestMe
			switch (format->wBitsPerSample) {
				case 8: g.sample_format = SAMPLE_FORMAT_S8; break;
				case 16: g.sample_format = SAMPLE_FORMAT_S16; break;
			}
		}
		else if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
			WAVEFORMATEXTENSIBLE *fmt = (WAVEFORMATEXTENSIBLE*)format;
			if (fmt->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
				g.sample_format = SAMPLE_FORMAT_F32;
			}
			else if (fmt->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
				switch (fmt->Format.wBitsPerSample) {
					case 8: g.sample_format = SAMPLE_FORMAT_S8; break;
					case 16: g.sample_format = SAMPLE_FORMAT_S16; break;
				}
			}
			else {
				// @FixMe
				printf("***** WASAPI backend has an unknown format. Assuming float!!! *****\n");
				g.sample_format = SAMPLE_FORMAT_F32;
			}
		}
		
		audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, (REFERENCE_TIME)1e7, 0, format, NULL);
		audio_client->GetBufferSize(&buffer_frame_count);
		audio_client->GetService(__uuidof(IAudioRenderClient), (void**)&render_client);
		audio_client->GetService(__uuidof(ISimpleAudioVolume), (void**)&g.volume_controller);
		render_client->GetBuffer(buffer_frame_count, &buffer);
		render_client->ReleaseBuffer(buffer_frame_count, 0);
		
		buffer_duration_ms = (format->nSamplesPerSec*1000) / buffer_frame_count;
		
		info->channels = format->nChannels;
		info->sample_rate = format->nSamplesPerSec;
		info->buffer_duration_ms = buffer_duration_ms;
		info->delay_ms = buffer_duration_ms / 2;

		sample_rate = info->sample_rate;
		channels = info->channels;

		// Device is ready for streaming
		ReleaseSemaphore(g.ready_sem, 1, NULL);
	}

	audio_client->Start();
	while (1) {
		u32 frame_padding;
		u32 available_frames = 0;
		u32 capture_packet_size = 0;
		
		// Wait for half of buffer duration, or handle interrupt signal.
		if (WaitForSingleObject(g.interrupt_sem, buffer_duration_ms/2) != WAIT_TIMEOUT) {	
			// Upon an interruption, stop the stream and reset the audio clock
			audio_client->Stop();
			audio_client->Reset();
			audio_client->Start();
		}
		
		if (g.want_kill) break;
		
		audio_client->GetCurrentPadding(&frame_padding);
		available_frames = buffer_frame_count - frame_padding;
		
		render_client->GetBuffer(available_frames, &buffer);
		//g.callback((float*)buffer, available_frames, g.callback_data);
		fill_buffer(buffer, available_frames);
		render_client->ReleaseBuffer(available_frames, 0);
	}
	
	CoTaskMemFree(format);
	SAFE_RELEASE(render_client);
	SAFE_RELEASE(audio_client);
	SAFE_RELEASE(device);

	return 0;
}

int32_t audio_run(Audio_Callback *callback, void *callback_data, Audio_Stream_Info *info) {
	HRESULT result;

	(void)OleInitialize(NULL);
	(void)CoInitializeEx(NULL, COINIT_MULTITHREADED);

	result = CoCreateInstance(
		__uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
		__uuidof(IMMDeviceEnumerator), (void**)&g.device_enumerator
	);

	if (FAILED(result))
		return 0;

	g.callback = callback;
	g.callback_data = callback_data;
	g.interrupt_sem = CreateSemaphore(NULL, 0, 1, NULL);
	g.ready_sem = CreateSemaphore(NULL, 0, 1, NULL);
	g.callback_data = callback_data;
	g.thread = CreateThread(NULL, 0, &audio_thread_proc, info, 0, NULL);
	WaitForSingleObject(g.ready_sem, INFINITE);

	return 1;
}

void audio_kill() {
	g.want_kill = true;
	audio_interrupt();
}

void audio_interrupt() {
	ReleaseSemaphore(g.interrupt_sem, 1, 0);
}

void audio_set_volume(float vol) {
	if (g.volume_controller) {
		g.volume_controller->SetMasterVolume(vol, NULL);
	}
}

float audio_get_volume() {
	if (g.volume_controller) {
		float vol;
		g.volume_controller->GetMasterVolume(&vol);
		return vol;
	}
	return 1.f;
}
