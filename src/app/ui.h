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
#ifndef UI_H
#define UI_H

#include "common.h"
#include "stream.h"
#include "files.h"
#include "util/auto_array.h"
#include "tracklist.h"
#include <imgui.h>

enum {
	GLOBAL_HOTKEY_PREVIOUS_TRACK,
	GLOBAL_HOTKEY_TOGGLE_PLAYBACK,
	GLOBAL_HOTKEY_NEXT_TRACK,
};

struct Track_Drag_Drop_Payload {
	Path_Pool path_pool;
	Auto_Array<Path_Ref> paths;
};

void init_ui();
// Returns false when the user wants to exit
bool show_ui();
void ui_add_to_library(Track& track);
void ui_next_track();
void ui_handle_hotkey(uintptr_t hotkey);

void ui_accept_drag_drop(const Track_Drag_Drop_Payload *payload);

// Not thread-safe
void ui_set_thumbnail(void *texture);
void ui_set_waveform_image(void *texture);
// ---------------

#endif //UI_H
