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
#ifndef CLIENT_H
#define CLIENT_H
#include "common.h"
extern "C" {
#include <libavutil/samplefmt.h>
}

#define AUDIO_DEVICE_NAME_LENGTH 64
#define AUDIO_CLIENT_MAX_IMPL_DATA_SIZE 256

enum Audio_Client_ID {
	AUDIO_CLIENT_NONE,
	AUDIO_CLIENT_WASAPI,
	AUDIO_CLIENT__COUNT,
};

typedef wchar_t Audio_Device_Name[AUDIO_DEVICE_NAME_LENGTH];
typedef void Audio_Stream_Callback(void *data, uint32 sample_count, uint8 *buffers[]);

struct Audio_Stream_Spec {
	AVSampleFormat sample_format;
	uint32 sample_rate;
	uint32 channel_count;
	uint32 buffer_frame_count;
};

struct Audio_Client_Stream {
	Audio_Client_ID client_type;
	Audio_Stream_Spec spec;
	Audio_Stream_Callback *callback;
	void *callback_data;
	ALIGNED(16) uint8 impl_data[AUDIO_CLIENT_MAX_IMPL_DATA_SIZE];
	
	Audio_Client_Stream() {}
	
	Audio_Client_Stream(Audio_Client_ID client_type_, Audio_Stream_Callback *callback_, void *callback_data_) {
		client_type = client_type_;
		callback = callback_;
		callback_data = callback_data_;
	}

	virtual void set_volume(float volume) = 0;
	virtual float get_volume() = 0;
	virtual void interrupt() = 0;
	virtual void close() = 0;
};

struct Audio_Client_Stream_WASAPI : Audio_Client_Stream {
	using Audio_Client_Stream::Audio_Client_Stream;
	void set_volume(float volume);
	float get_volume();
	void interrupt();
	void close();
};

struct Audio_Memory_Stream : Audio_Client_Stream {
	float *buffers[2];
	Audio_Memory_Stream(uint32 sample_rate);
	void allocate_buffers(uint32 buffer_frames);
	void set_volume(float volume);
	float get_volume();
	void interrupt();
	void close();
};

struct Audio_Client {
	// Should return true on success
	bool (*init)();
	uint32 (*get_device_count)();
	void (*get_device_name)(uint32 index, Audio_Device_Name buffer);
	// Get the index of the default device
	uint32 (*get_default_device)();
	Audio_Client_Stream *(*open_device)(uint32 device_index,
						Audio_Stream_Callback *callback, void *callback_data);
	// Set volume between 0 and 1
	void (*set_volume)(float volume);
	void (*interrupt)();
	void (*destroy)();
};

bool get_audio_client(Audio_Client_ID type, Audio_Client *client);

#endif //CLIENT_H
