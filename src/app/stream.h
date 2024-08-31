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
#ifndef STREAM_H
#define STREAM_H

#include "audio_client.h"

// The stream API manages loading and playing audio files as well effects such as crossfading.

enum Stream_State {
	STREAM_STATE_STOPPED,
	STREAM_STATE_PLAYING,
	STREAM_STATE_PAUSED,
	STREAM_STATE__COUNT,
};

#define THUMBNAIL_WIDTH 512
#define THUMBNAIL_HEIGHT 512
#define WAVEFORM_IMAGE_HEIGHT 128

bool stream_open(Audio_Client_ID client, const char *preferred_device = nullptr);

bool stream_load(const char *file_path);
void stream_flush_events();

// always RGBA format
bool stream_extract_thumbnail(const char *filename, int requested_size, Image *out);
bool stream_get_thumbnail(Image *th);
void stream_free_thumbnail(Image *th);
void stream_get_waveform(Image *image);

void stream_crossfade();
void stream_play_next();
void stream_set_crossfade_time(int32 milliseconds);
int32 stream_get_crossfade_time();
bool stream_file_is_supported(const char *file_path);
Stream_State stream_get_state();
void stream_toggle_playing();
void stream_set_volume(float volume);
float stream_get_volume();
int64 stream_get_pos(); // In seconds
int64 stream_get_duration(); // In seconds
void stream_seek(int64 second);
void stream_close();

#endif
