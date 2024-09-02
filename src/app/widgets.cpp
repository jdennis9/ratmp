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
#include <imgui.h>
#include <imgui_internal.h>
#include <ctype.h>
#include "widgets.h"
#include "theme.h"
#include "ui.h"

// Trim spaces from string
static void trim_string(const char *str, char *buffer, int buffer_size) {
	while (*str && isspace(*str)) str++;
	if (!*str) return;
	int written = 0;
	
	while (*str && !isspace(*str) && written < (buffer_size-1)) {
		buffer[written] = *str;
		str++;
		written++;
	}
	
	buffer[written] = 0;
}

static void *settings_open_fn(ImGuiContext *ctx, ImGuiSettingsHandler *handler, const char *name) {
	UI_Window window = ui_get_window_from_name(name);
	// Have to add 1 because returning NULL causes ImGui to ignore this entry
	return (void*)(uintptr_t)(window + 1);
}

static void settings_read_line_fn(ImGuiContext *ctx, ImGuiSettingsHandler *handler, 
								  void *entry, const char *line) {
	// -1 because we added 1 in settings_open_fn()
	UI_Window window = (UI_Window)((uintptr_t)entry - 1);
	if (window >= UI_WINDOW__COUNT) return;
	const char *name_ptr = line;
	const char *value_ptr = strchr(line, '=');
	if (!value_ptr) return;
	value_ptr++;
	
	char name[8];
	char value[8];
	
	trim_string(name_ptr, name, sizeof(name));
	trim_string(value_ptr, value, sizeof(value));
	
	if (!strcmp(name, "Open")) {
		int open = atoi(value);
		if (open) ui_show_window(window);
	}
}

static void settings_write_fn(ImGuiContext *ctx, ImGuiSettingsHandler *handler, ImGuiTextBuffer *buf) {
	for (uint32 window = 0; window < UI_WINDOW__COUNT; ++window) {
		buf->appendf("[RatMP][%s]\n", ui_get_window_name((UI_Window)window));
		buf->appendf("Open = %u\n", ui_is_window_open((UI_Window)window));
	}
}

void install_imgui_settings_handler() {
	ImGuiSettingsHandler handler = {};
	handler.TypeName = "RatMP";
	handler.TypeHash = ImHashStr(handler.TypeName);
	handler.ReadOpenFn = &settings_open_fn;
	handler.ReadLineFn = &settings_read_line_fn;
	handler.WriteAllFn = &settings_write_fn;
	
	ImGui::AddSettingsHandler(&handler);
}

bool seek_slider(const char *name, int64 position, int64 length, int64 *p_new_position, float thickness, void *waveform) {
	ImDrawList *draw_list = ImGui::GetWindowDrawList();
	ImVec2 available_size = ImGui::GetContentRegionAvail();
	ImVec2 cursor = ImGui::GetCursorScreenPos();
	float progress = (float)position / (float)length;
	ImGuiID id = ImGui::GetID(name);
	bool active = false;
	ImGuiStyle style = ImGui::GetStyle();
	ImVec2 size = {available_size.x - style.WindowPadding.x, thickness};

	ImGui::PushID(id);

	cursor.x += style.ItemInnerSpacing.x;
	cursor.y += style.ItemInnerSpacing.y/2;
	
	if (waveform) {
		ImTextureID waveform_texture = (ImTextureID)waveform;
		float played_size = size.x * progress;
		float played_uv_max = progress;
		float remaining_size = size.x * (1.f-progress);
		draw_list->AddImageQuad(waveform_texture,
								ImVec2{cursor.x, cursor.y},// top-left
								ImVec2{cursor.x + size.x, cursor.y}, // top-right
								ImVec2{cursor.x + size.x, cursor.y + size.y}, // bottom-left
								ImVec2{cursor.x, cursor.y + size.y}, // bottom-right
								ImVec2{1, 0},
								ImVec2{1, 1},
								ImVec2{0, 1},
								ImVec2{0, 0},
								get_theme_color(THEME_COLOR_SEEK_BAR_BG)
								);
		draw_list->AddImageQuad(waveform_texture,
								cursor, // top-left
								ImVec2{cursor.x + played_size, cursor.y}, // top-right
								ImVec2{cursor.x + played_size, cursor.y + size.y}, // bottom-left
								ImVec2{cursor.x, cursor.y + size.y}, // bottom-right
								ImVec2{1, 0},
								ImVec2{1, played_uv_max},
								ImVec2{0, played_uv_max},
								ImVec2{0, 0},
								get_theme_color(THEME_COLOR_SEEK_BAR)
								);
		
	} else {
		draw_list->AddRectFilled(cursor, 
								 ImVec2{cursor.x + size.x, cursor.y + size.y}, 
								 get_theme_color(THEME_COLOR_SEEK_BAR_BG));
		draw_list->AddRectFilled(cursor, 
								 ImVec2{cursor.x + (size.x * progress), cursor.y + size.y}, 
								 get_theme_color(THEME_COLOR_SEEK_BAR));
	}
	
	if (ImGui::InvisibleButton("##seek_button", size)) {
		ImVec2 mouse = ImGui::GetMousePos();
		*p_new_position = ((mouse.x - cursor.x) / size.x) * length;
		active = true;
	}
	
	if (ImGui::IsItemHovered()) {
		ImGui::SetMouseCursor(ImGuiMouseCursor_Hand);
	}
	
	ImGui::PopID();
	
	return active;
}

static inline float scale_volume(float v) {
	//return v * v;
	return v;
}

static inline float reverse_scale_volume(float v) {
	//return sqrtf(v);
	return v;
}

bool volume_slider(const char *name, float *p_position, float width) {
	ImDrawList *draw_list = ImGui::GetWindowDrawList();
	ImGuiWindow *window = ImGui::GetCurrentWindow();
	ImVec2 available_size = ImGui::GetContentRegionAvail();
	ImVec2 size = {width, 12.f};
	ImVec2 cursor = ImGui::GetCursorScreenPos();
	ImGuiID id = ImGui::GetID(name);
	bool active = id == ImGui::GetActiveID();
	ImVec2 mouse = ImGui::GetMousePos();
	float position = reverse_scale_volume(*p_position);
	ImRect bb;
	ImGuiStyle style = ImGui::GetStyle();

	cursor.x += style.ItemInnerSpacing.x;
	cursor.y += style.ItemInnerSpacing.y;

	bb.Min = cursor;
	bb.Max = ImVec2{cursor.x + size.x, cursor.y + size.y};
	
	ImGui::PushID(id);
	
	draw_list->AddTriangleFilled(ImVec2{cursor.x, cursor.y + size.y},
								 ImVec2{cursor.x + size.x, cursor.y},
								 ImVec2{cursor.x + size.x, cursor.y + size.y},
								 get_theme_color(THEME_COLOR_SEEK_BAR_BG)
								 );
	
	draw_list->AddTriangleFilled(ImVec2{cursor.x, cursor.y + size.y},
								 ImVec2{cursor.x + (size.x*position), cursor.y + (size.y - position*size.y)},
								 ImVec2{cursor.x + (size.x*position), cursor.y + size.y},
								 get_theme_color(THEME_COLOR_SEEK_BAR)
								 );
	
	if (ImGui::InvisibleButton(name, size, ImGuiButtonFlags_PressedOnClick|ImGuiButtonFlags_Repeat)) {
		active = true;
		ImGui::SetActiveID(id, window);
	}
	
	ImGui::SetCursorScreenPos(ImVec2{cursor.x + size.x, cursor.y});
	
	if ((ImGui::IsMouseClicked(ImGuiMouseButton_Left) || ImGui::IsMouseDragging(ImGuiMouseButton_Left)) && active) {
		*p_position = ImClamp((mouse.x - cursor.x) / size.x, 0.f, 1.f);
		*p_position = scale_volume(*p_position);
	}
	
	if (active && ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
		ImGui::ClearActiveID();
		active = false;
	}
	
	if (active) {
		ImGui::SetActiveID(id, window);
	}
	
	ImGui::PopID();
	
	ImGui::SameLine();
	//ImGui::Text(u8"\xf028");
	
	return active;
}

bool vertical_volume_slider(const char *str_id, const ImVec2 &size, float *p_value, float min, float max) {
	ImDrawList *draw_list = ImGui::GetWindowDrawList();
	ImGuiWindow *window = ImGui::GetCurrentWindow();
	ImVec2 available_size = ImGui::GetContentRegionAvail();
	ImVec2 cursor = ImGui::GetCursorScreenPos();
	ImGuiID id = ImGui::GetID(str_id);
	bool active = id == ImGui::GetActiveID();
	ImVec2 mouse = ImGui::GetMousePos();
	float position = reverse_scale_volume(*p_value);
	ImRect bb;
	ImGuiStyle style = ImGui::GetStyle();
	float factor = (position - min) / (max - min);

	//cursor.x += style.ItemInnerSpacing.x;
	//cursor.y += style.ItemInnerSpacing.y;
	bb.Min = cursor;
	bb.Max = ImVec2{cursor.x + size.x, cursor.y + size.y};

	ImGui::PushID(id);

	if (ImGui::InvisibleButton(str_id, size, ImGuiButtonFlags_PressedOnClick | ImGuiButtonFlags_Repeat)) {
		active = true;
		ImGui::SetActiveID(id, window);
	}

	if ((ImGui::IsMouseClicked(ImGuiMouseButton_Left) || ImGui::IsMouseDragging(ImGuiMouseButton_Left)) && active) {
		factor = 1.f - ImClamp((mouse.y - cursor.y) / size.y, 0.f, 1.f);
		*p_value = ImLerp(min, max, factor);
		*p_value = scale_volume(*p_value);
	}

	if (active && ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
		ImGui::ClearActiveID();
		active = false;
	}

	if (active) {
		ImGui::SetActiveID(id, window);
	}

	draw_list->AddRectFilled(
		cursor,
		ImVec2{cursor.x + size.x, cursor.y + size.y},
		get_theme_color(THEME_COLOR_SEEK_BAR_BG));
	draw_list->AddRectFilled(
		ImVec2{cursor.x, cursor.y + (size.y * (1.f - factor))},
		ImVec2{cursor.x + size.x, cursor.y + size.y},
		get_theme_color(THEME_COLOR_SEEK_BAR));

	ImGui::PopID();

	return active;
}

bool small_selectable(const char *text, bool selected) {
	ImVec2 text_size = ImGui::CalcTextSize(text);
	return ImGui::Selectable(text, selected, 0, text_size);
}

bool small_selectable(const char *text, bool *p_value) {
	ImVec2 text_size = ImGui::CalcTextSize(text);
	return ImGui::Selectable(text, p_value, 0, text_size);
}

typedef void Small_Button_Draw_Hook(ImDrawList *draw_list, ImVec2 pos, ImVec2 size);

// Small button with an icon that is drawn via a hook rather a glyph or image
static bool special_small_button(const char *str_id, Small_Button_Draw_Hook *draw, ImVec2 size, uint32 hover_color) {
	ImDrawList *draw_list = ImGui::GetWindowDrawList();
	ImGuiWindow *window = ImGui::GetCurrentWindow();
	ImGuiID id = ImGui::GetID(str_id);
	bool active = false;
	ImVec2 pos = ImGui::GetCursorScreenPos();
	
	ImGui::PushID(id);
	if (ImGui::InvisibleButton(str_id, size, 0)) {
		active = true;
		ImGui::SetActiveID(id, window);
	}
	
	if (ImGui::IsItemHovered()) {
		draw_list->AddRectFilled(pos, ImVec2{pos.x + size.x, pos.y + size.y}, hover_color);
	}
	
	draw(draw_list, pos, size);
	
	ImGui::PopID();
	
	return active;
}

bool circle_handle_slider(const char *str_id, float *p_position, float min, float max, float width) {
	ImDrawList *draw_list = ImGui::GetWindowDrawList();
	ImGuiWindow *window = ImGui::GetCurrentWindow();
	ImVec2 available_size = ImGui::GetContentRegionAvail();
	ImVec2 cursor = ImGui::GetCursorScreenPos();
	ImVec2 mouse = ImGui::GetMousePos();
	float rel_pos = (*p_position - min) / (max - min);
	ImGuiID id = ImGui::GetID(str_id);
	bool active = id == ImGui::GetActiveID();
	ImGuiStyle& style = ImGui::GetStyle();
	ImVec2 text_size = ImGui::CalcTextSize(str_id);
	
	const float handle_radius = 6.f;
	ImVec2 size = {width, 6.f};
	ImVec2 bg_pos = {
		cursor.x, 
		cursor.y + style.ItemInnerSpacing.y + (ImGui::GetTextLineHeight()*.5f) - size.y,
	};
	ImVec2 handle_center = {bg_pos.x + (size.x * rel_pos), bg_pos.y + (size.y*.5f)};
	
	ImVec2 text_pos = {cursor.x + width + style.ItemInnerSpacing.x + handle_radius + 2.f, cursor.y};
	draw_list->AddText(text_pos, ImGui::GetColorU32(style.Colors[ImGuiCol_Text]), str_id);
	
	draw_list->AddRectFilled(bg_pos,
							 ImVec2{bg_pos.x + size.x, bg_pos.y + size.y},
							 ImGui::GetColorU32(style.Colors[ImGuiCol_Header]), 4.f);
	draw_list->AddRectFilled(bg_pos,
							 ImVec2{bg_pos.x + (size.x * rel_pos), bg_pos.y + size.y},
							 ImGui::GetColorU32(style.Colors[ImGuiCol_HeaderActive]), 4.f);
	
	draw_list->AddCircleFilled(handle_center,
							   handle_radius,
							   ImGui::GetColorU32(style.Colors[ImGuiCol_HeaderActive]));
	
	
	
	ImGui::PushID(id);
	ImVec2 clickbox_size = {
		size.x + (style.ItemInnerSpacing.x * 2.f),
		size.y + (style.ItemInnerSpacing.y * 2.f),
	};
	if (ImGui::InvisibleButton(str_id, clickbox_size,
							   ImGuiButtonFlags_PressedOnClick|ImGuiButtonFlags_Repeat)) {
		active = true;
		ImGui::SetActiveID(id, window);
	}
	
	if (active &&
		(ImGui::IsMouseClicked(ImGuiMouseButton_Left)||ImGui::IsMouseDown(ImGuiMouseButton_Left))) {
		rel_pos = ImClamp((mouse.x - cursor.x) / size.x, 0.f, 1.f);
		*p_position = ImLerp(min, max, rel_pos);
	}
	
	if (active && ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
		ImGui::ClearActiveID();
		active = false;
	}
	
	if (active) {
		ImGui::SetActiveID(id, window);
	}
	
	if (active || ImGui::IsItemHovered()) {
		ImGui::SetMouseCursor(ImGuiMouseCursor_Hand);
	}
	ImGui::PopID();
	
	return active;
}

