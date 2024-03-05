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
#ifndef MAIN_H
#define MAIN_H

#include "common.h"
#include "theme.h"

enum Close_Policy {
	CLOSE_POLICY_QUERY,
	CLOSE_POLICY_EXIT,
	CLOSE_POLICY_EXIT_TO_TRAY,
	CLOSE_POLICY__COUNT,
};

enum Event_Code {
	EVENT_STREAM_END_OF_TRACK,
	EVENT_STREAM_THUMBNAIL_READY,
	EVENT_STREAM_WAVEFORM_READY,
	EVENT_STREAM_TRACK_LOADED,
};

struct Config {
	char theme[MAX_THEME_NAME_LENGTH + 1];
	Close_Policy close_policy;
};

extern Config g_config;

void load_config();
void save_config();
void apply_config();

// Pass in NULL to unload background image
void load_background_image(const char *filename);
// Returns NULL is no background is loaded
const char *get_background_image_path();

// Path is relative to fonts folder e.g liberation-mono.ttf -> fonts\\liberation-mono.ttf.
// This is for portability, so the user doesn't need to store fonts elsewhere to be able to move the
// program and not lose their theme fonts.
void set_font(const char *path);
const char *get_font();
void set_font_size(int size);
int get_font_size();

void post_event(Event_Code event, int64 wparam, int64 lparam);
void close_window_to_tray();

#endif //MAIN_H
