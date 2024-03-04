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
#include "wasapi.h"
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <assert.h>
#include <Functiondiscoverykeys_devpkey.h>
#include <wchar.h>

struct Stream_WASAPI {
	 //*volume_controller;
	HANDLE ready_semaphore;
	HANDLE interrupt_semaphore;
	HANDLE thread;
	IAudioStreamVolume *volume_controller;
	bool want_close;
};

static struct {
	IMMDeviceEnumerator *device_enumerator;
	IMMDeviceCollection *device_collection;
} G;

// Check result and return ret_val if the result is an error
#define CHECK(result, ret_val) if (result != S_OK) return ret_val;
#define SAFE_RELEASE(obj) if (obj) { (obj)->Release(); (obj) = nullptr; }

bool wasapi_init() {
	//CHECK(CoInitializeEx(NULL, COINITBASE_MULTITHREADED), false);
	CHECK(CoCreateInstance(__uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), 
		(void**)&G.device_enumerator), false);
	if (G.device_enumerator->EnumAudioEndpoints(EDataFlow::eRender, DEVICE_STATE_ACTIVE, &G.device_collection) != S_OK) {
		SAFE_RELEASE(G.device_enumerator);
		return false;
	}

	return true;
}

uint32 wasapi_get_device_count() {
	UINT count;
	G.device_collection->GetCount(&count);
	return count;
}

void wasapi_get_device_name(uint32 index, Audio_Device_Name name) {
	IMMDevice *device;
	IPropertyStore *properties;
	PROPVARIANT prop_value;

	G.device_collection->Item(index, &device);
	device->OpenPropertyStore(STGM_READ, &properties);
	properties->GetValue(PKEY_DeviceInterface_FriendlyName, &prop_value);
	wcsncpy(name, prop_value.pwszVal, AUDIO_DEVICE_NAME_LENGTH);
	device->Release();
	properties->Release();
}

void Audio_Client_Stream_WASAPI::set_volume(float volume) {
	Stream_WASAPI *impl = (Stream_WASAPI*)this->impl_data;
	float volumes[8] = {volume,volume,volume,volume,volume,volume,volume,volume};
	if (impl->volume_controller) impl->volume_controller->SetAllVolumes(this->spec.channel_count, volumes);
}

float Audio_Client_Stream_WASAPI::get_volume() {
	Stream_WASAPI *impl = (Stream_WASAPI *)this->impl_data;
	float volume;
	if (impl->volume_controller) impl->volume_controller->GetChannelVolume(0, &volume);
	return volume;
}

void Audio_Client_Stream_WASAPI::interrupt() {
	Stream_WASAPI *impl = (Stream_WASAPI*)this->impl_data;
	ReleaseSemaphore(impl->interrupt_semaphore, 1, 0);
}

void Audio_Client_Stream_WASAPI::close() {
	Stream_WASAPI *impl = (Stream_WASAPI*)this->impl_data;
	impl->want_close = true;
	this->interrupt();
	WaitForSingleObject(impl->ready_semaphore, INFINITE);
	CloseHandle(impl->thread);
}

static DWORD audio_thread_entry(LPVOID user) {
	WAVEFORMATEX *format;
	uint32 buffer_frame_count;
	IMMDevice *device;
	IAudioClient *audio_client;
	IAudioRenderClient *render_client;
	uint8 *buffer;
	Audio_Client_Stream *stream = (Audio_Client_Stream *)user;
	Stream_WASAPI *impl = (Stream_WASAPI *)stream->impl_data;

	{
		// @Note: stream is invalidated after ready semaphore is signaled
		G.device_enumerator->GetDefaultAudioEndpoint(EDataFlow::eRender, ERole::eConsole, &device);
		device->Activate(__uuidof(audio_client), CLSCTX_ALL, NULL, (void **)&audio_client);
		audio_client->GetMixFormat(&format);

		audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, (REFERENCE_TIME)1e7, 0, format, NULL);
		audio_client->GetBufferSize(&buffer_frame_count);
		audio_client->GetService(__uuidof(IAudioRenderClient), (void**)&render_client);
		audio_client->GetService(__uuidof(IAudioStreamVolume), (void**)&impl->volume_controller);
		render_client->GetBuffer(buffer_frame_count, &buffer);
		render_client->ReleaseBuffer(buffer_frame_count, 0);
		
		stream->spec.channel_count = format->nChannels;
		stream->spec.sample_format = AV_SAMPLE_FMT_FLT; // @TODO: Check for non-float format
		stream->spec.sample_rate = format->nSamplesPerSec;
		stream->spec.buffer_frame_count = buffer_frame_count;
		
		// Device is ready for streaming
		ReleaseSemaphore(impl->ready_semaphore, 1, NULL);
	}

	const DWORD buffer_duration_ms = (format->nSamplesPerSec*1000) / buffer_frame_count;

	audio_client->Start();
	while (1) {
		uint32 frame_padding;
		uint32 available_frames = 0;
		
		// Wait for half of buffer duration, or handle interrupt signal.
		if (WaitForSingleObject(impl->interrupt_semaphore, buffer_duration_ms/2) != WAIT_TIMEOUT) {	
			// Upon an interruption, stop the stream and reset the audio clock
			audio_client->Stop();
			audio_client->Reset();
			audio_client->Start();
		}

		if (impl->want_close) break;

		audio_client->GetCurrentPadding(&frame_padding);
		available_frames = buffer_frame_count - frame_padding;

		render_client->GetBuffer(available_frames, &buffer);
		stream->callback(stream->callback_data, available_frames, &buffer);
		render_client->ReleaseBuffer(available_frames, 0);
	}

	ReleaseSemaphore(impl->ready_semaphore, 1, 0);
	CoTaskMemFree(format);
	CloseHandle(impl->ready_semaphore);
	SAFE_RELEASE(render_client);
	SAFE_RELEASE(impl->volume_controller);
	SAFE_RELEASE(audio_client);
	SAFE_RELEASE(device);

	return 0;
}

Audio_Client_Stream *wasapi_open_device(uint32 device_index, Audio_Stream_Callback *callback, void *callback_data) {
	Audio_Client_Stream *stream = new Audio_Client_Stream_WASAPI(AUDIO_CLIENT_WASAPI, callback, callback_data);
	Stream_WASAPI *impl = (Stream_WASAPI *)stream->impl_data;
	impl->interrupt_semaphore = CreateSemaphore(NULL, 0, 1, NULL);
	impl->ready_semaphore = CreateSemaphore(NULL, 0, 1, NULL);
	impl->thread = CreateThread(NULL, 256 << 10, &audio_thread_entry, stream, 0, NULL);
	impl->want_close = false;
	WaitForSingleObject(impl->ready_semaphore, INFINITE);
	return stream;
}

void wasapi_close_device() {
}

void wasapi_destroy() {
	SAFE_RELEASE(G.device_enumerator);
	SAFE_RELEASE(G.device_collection);
}
