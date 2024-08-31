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
	EVENT_STREAM_TRACK_LOAD_FAILED,
	EVENT_REQUEST_SHOW_WINDOW,
};

enum Glyph_Range {
	GLYPH_RANGE_JAPANESE,
	GLYPH_RANGE_KOREAN,
	GLYPH_RANGE_CYRILLIC,
	GLYPH_RANGE_GREEK,
	GLYPH_RANGE_CHINESE,
	GLYPH_RANGE_VIETNAMESE,
	GLYPH_RANGE_THAI,
	GLYPH_RANGE__COUNT,
};

#define USE_GLYPH_RANGE_NAMES(name) const char *name[GLYPH_RANGE__COUNT];\
name[GLYPH_RANGE_JAPANESE] = "Japanese";\
name[GLYPH_RANGE_KOREAN] = "Korean";\
name[GLYPH_RANGE_CYRILLIC] = "Cyrillic";\
name[GLYPH_RANGE_GREEK] = "Greek";\
name[GLYPH_RANGE_CHINESE] = "Chinese";\
name[GLYPH_RANGE_VIETNAMESE] = "Vietnamese";\
name[GLYPH_RANGE_THAI] = "Thai";\

#define MIN_THUMBNAIL_SIZE 64
#define MAX_THUMBNAIL_SIZE 1024
#define MIN_PREVIEW_THUMBNAIL_SIZE 32
#define MAX_PREVIEW_THUMBNAIL_SIZE 256
#define MIN_WAVEFORM_WIDTH_POWER 4
#define MAX_WAVEFORM_WIDTH_POWER 9
#define MIN_WAVEFORM_HEIGHT_POWER 9
#define MAX_WAVEFORM_HEIGHT_POWER 12

struct Config {
	char theme[MAX_THEME_NAME_LENGTH + 1];
	Close_Policy close_policy;
	bool include_glyphs[GLYPH_RANGE__COUNT];
	int thumbnail_size;
	int preview_thumbnail_size;
	int waveform_width_power;
	int waveform_height_power;
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
void set_icon_font_size(int size);
int get_font_size();
int get_icon_font_size();

void post_event(Event_Code event, int64 wparam, int64 lparam);
void close_window_to_tray();

#endif //MAIN_H
