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
#ifndef WIDGETS_H
#define WIDGETS_H

//=====================================================================
// Custom ImGui widgets
//=====================================================================

#include "common.h"
#include <imgui.h>

bool seek_slider(const char *name, int64 position, int64 length, int64 *p_new_position, float thickness, ImTextureID waveform_image = 0);
bool volume_slider(const char *name, float *p_position, float width);
bool vertical_volume_slider(const char *str_id, const ImVec2& size, float *p_value, float min, float max);
bool small_selectable(const char *text, bool selected = false);
bool small_selectable(const char *text, bool *p_value);
bool minimize_button(const char *id, float width);
bool maximize_button(const char *id, float width);
bool exit_button(const char *id, float width);
bool circle_handle_slider(const char *name, float *p_position, float min, float max, float width);

#endif //WIDGETS_H
