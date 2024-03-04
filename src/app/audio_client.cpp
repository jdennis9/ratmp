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
#include "audio_client.h"
#include "audio_clients/wasapi.h"
#include <stdlib.h>

bool get_audio_client(Audio_Client_ID type, Audio_Client *client) {
	switch (type) {
	case AUDIO_CLIENT_WASAPI:
		client->init = &wasapi_init;
		client->get_device_count = &wasapi_get_device_count;
		client->get_device_name = &wasapi_get_device_name;
		client->open_device = &wasapi_open_device;
		client->destroy = &wasapi_destroy;
		break;
	}

	return true;
}

Audio_Memory_Stream::Audio_Memory_Stream(uint32 sample_rate) {
	spec.sample_format = AV_SAMPLE_FMT_FLTP;
	spec.sample_rate = sample_rate;
	spec.channel_count = 2;
}

void Audio_Memory_Stream::allocate_buffers(uint32 frames) {
	uint32 sample_size = 4;
	buffers[0] = (float*)malloc(frames * sample_size);
	buffers[1] = (float*)malloc(frames * sample_size);
}

void Audio_Memory_Stream::set_volume(float volume) {
}

float Audio_Memory_Stream::get_volume() {
	return 1.f;
}

void Audio_Memory_Stream::interrupt() {
}

void Audio_Memory_Stream::close() {
	if (buffers[0]) {
		free(buffers[0]);
		free(buffers[1]);
	}
}
	