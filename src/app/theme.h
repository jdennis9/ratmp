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
#ifndef THEME_H
#define THEME_H

#include "common.h"

#define MAX_THEME_NAME_LENGTH 127

enum Theme_Color {
	THEME_COLOR_PLAYING_INDICATOR,
	THEME_COLOR_PLAYING_TEXT,
	THEME_COLOR_SEEK_BAR,
	THEME_COLOR_SEEK_BAR_BG,
	THEME_COLOR_TRACK_PREVIEW,
	THEME_COLOR_VOLUME_SLIDER,
	THEME_COLOR__COUNT,
};

void set_default_theme();
void load_theme(const char *name);
void save_theme(const char *name);
// Returns true if there are unsaved theme changes
bool show_theme_editor_gui();
const char *show_theme_selector_gui();
const char *get_loaded_theme();
uint32 get_theme_color(Theme_Color color);

#endif //THEME_H
