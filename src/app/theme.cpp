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
#include "theme.h"
#include "files.h"
#include "util/auto_array_impl.h"
#include "main.h"
#include <imgui.h>
#include <ini.h>
#include <assert.h>

struct Font_Name {
	char name[128];
};

struct Theme {
	char name[MAX_THEME_NAME_LENGTH+1];
	char font[512];
};

static ImVec4 g_theme_colors[THEME_COLOR__COUNT];

static const struct Color_Info {
	ImGuiCol color;
	const char *name;
	const char *ini_name;
} g_color_info[] = {
	{ImGuiCol_Text, "Text", "Text"},
	{ImGuiCol_WindowBg, "Bg.", "Bg"},
	{ImGuiCol_PopupBg, "Popup", "Popup"},
	{ImGuiCol_Border, "Borders", "Borders"},
	{ImGuiCol_TitleBg, "Title Bar", "TitleBar"},
	{ImGuiCol_TitleBgActive, "Title Bar (Active)", "TitleBarActive"},
	{ImGuiCol_MenuBarBg, "Menu Bar", "MenuBar"},
	{ImGuiCol_TableHeaderBg, "Table Header", "TableHeader"},
	{ImGuiCol_TableRowBgAlt, "Alt Table Bg.", "AltTableBg"},
	{ImGuiCol_TableBorderLight, "Table Borders", "TableBorders"},
	{ImGuiCol_FrameBg, "Frame", "Frame"},
	{ImGuiCol_FrameBgHovered, "Frame (Hovered)", "FrameHovered"},
	{ImGuiCol_FrameBgActive, "Frame (Active)", "FrameActive"},
	{ImGuiCol_Header, "Header", "Header"},
	{ImGuiCol_HeaderHovered, "Header (Hovered)", "HeaderHovered"},
	{ImGuiCol_HeaderActive, "Header (Active)", "HeaderActive"},
	{ImGuiCol_Button, "Button", "Button"},
	{ImGuiCol_ButtonHovered, "Button (Hovered)", "ButtonHovered"},
	{ImGuiCol_ButtonActive, "Button (Active)", "ButtonActive"},
	{ImGuiCol_Separator, "Separator", "Separator"},
	{ImGuiCol_Tab, "Tab", "Tab"},
	{ImGuiCol_TabHovered, "Tab (Hovered)", "TabHovered"},
	{ImGuiCol_TabActive, "Tab (Selected)", "TabSelected"},
	{ImGuiCol_ScrollbarGrab, "Scrollbar", "Scrollbar"},
	{ImGuiCol_ScrollbarGrabHovered, "Scrollbar (Hovered)", "ScrollbarHovered"},
	{ImGuiCol_ScrollbarGrabActive, "Scrollbar (Active)", "ScrollbarActive"},
	{ImGuiCol_ScrollbarBg, "Scrollbar Bg.", "ScrollbarBg"},
	{ImGuiCol_ResizeGrip, "Resize Grip", "ResizeGrip"},
	{ImGuiCol_ResizeGripHovered, "Resize Grip (Hovered)", "ResizeGripHovered"},
	{ImGuiCol_ResizeGripActive, "Resize Grip (Active)", "ResizeGripActive"},
	{ImGuiCol_COUNT + THEME_COLOR_PLAYING_INDICATOR, "Playing Indicator", "PlayingIndicator"},
	{ImGuiCol_COUNT + THEME_COLOR_PLAYING_TEXT, "Playing Text", "PlayingText"},
	{ImGuiCol_COUNT + THEME_COLOR_SEEK_BAR, "Seek Bar", "SeekBar"},
	{ImGuiCol_COUNT + THEME_COLOR_SEEK_BAR_BG, "Seek Bar Bg.", "SeekBarBg"},
	{ImGuiCol_COUNT + THEME_COLOR_TRACK_PREVIEW, "Track Preview.", "TrackPreview"},
};

static Auto_Array<Theme> g_themes;
static uint32 g_selected_theme;
static Auto_Array<Font_Name> g_fonts;
static uint32 g_selected_font;

static uint32 flip_endian(uint32 v) {
	uint32 ret;
	char *i = (char*)&v;
	char *o = (char*)&ret;
	o[0] = i[3];
	o[1] = i[2];
	o[2] = i[1];
	o[3] = i[0];
	return ret;
}

static int theme_ini_handler(void *data, const char *section, const char *key, const char *value) {
	ImGuiStyle& style = ImGui::GetStyle();
	
	if (!strcmp(section, "Colors")) {
		for (uint32 i = 0; i < ARRAY_LENGTH(g_color_info); ++i) {
			const Color_Info& info = g_color_info[i];
			
			if (!strcmp(key, info.ini_name)) {
				uint32 color = (uint32)strtoll(value, NULL, 16);
				color = flip_endian(color);
				
				if (info.color < ImGuiCol_COUNT) {
					style.Colors[info.color] = ImColor(color).Value;
				}
				else {
					g_theme_colors[info.color - ImGuiCol_COUNT] = ImColor(color).Value;
				}
				
				break;
			}
		}
	}
	else if (!strcmp(section, "Style")) {
		if (!strcmp(key, "BackgroundImage")) {
			load_background_image(value);
		}
		else if (!strcmp(key, "Font")) {
			set_font(value);
		}
		else if (!strcmp(key, "FontSize")) {
			set_font_size(atoi(value));
		}
		else if (!strcmp(key, "IconFontSize")) {
			set_icon_font_size(atoi(value));
		}
		else if (!strcmp(key, "WindowBorderSize"))
			style.WindowBorderSize = (float)atoi(value);
		else if (!strcmp(key, "ScrollbarRounding"))
			style.ScrollbarRounding = (float)atoi(value);
		else if (!strcmp(key, "FrameRounding"))
			style.FrameRounding = (float)atoi(value);
		else if (!strcmp(key, "ScrollbarSize"))
			style.ScrollbarSize = (float)atoi(value);
		else if (!strcmp(key, "WindowPaddingX"))
			style.WindowPadding.x = (float)atoi(value);
		else if (!strcmp(key, "WindowPaddingY"))
			style.WindowPadding.y = (float)atoi(value);
		else if (!strcmp(key, "CellPaddingX"))
			style.CellPadding.x = (float)atoi(value);
		else if (!strcmp(key, "CellPaddingY"))
			style.CellPadding.y = (float)atoi(value);
		else if (!strcmp(key, "FramePaddingX"))
			style.FramePadding.x = (float)atoi(value);
		else if (!strcmp(key, "FramePaddingY"))
			style.FramePadding.y = (float)atoi(value);
		else if (!strcmp(key, "ItemSpacingX"))
			style.ItemSpacing.x = (float)atoi(value);
		else if (!strcmp(key, "ItemSpacingY"))
			style.ItemSpacing.y = (float)atoi(value);
		else if (!strcmp(key, "WindowTitleAlign"))
			style.WindowTitleAlign.x = atof(value);
	}
	
	return true;
}

static bool add_theme_from_dir(const char *path) {
	const char *filename = get_file_name(path);
	uint32 length = get_file_name_length_without_extension(path);
	Theme name = {};
	assert(length < MAX_THEME_NAME_LENGTH);
	if (length == 0) return true;
	strncpy(name.name, filename, length);
	name.name[length] = 0;
	g_themes.append(name);
	
	return true;
}


static void refresh_themes() {
	g_themes.reset();
	for_each_file_in_directory(L"themes\\", &add_theme_from_dir, 1);
}

static bool add_font_from_dir(const char *path) {
	const char *filename = get_file_name(path);
	Font_Name name = {};
	strncpy(name.name, filename, sizeof(name.name) - 1);
	g_fonts.append(name);
	return true;
}

static void refresh_fonts() {
	bool update_selected_font = false;
	Font_Name current_font;
	if (g_fonts.length()) {
		strcpy(current_font.name, g_fonts[g_selected_font].name);
		update_selected_font = true;
	}
	
	g_fonts.reset();
	for_each_file_in_directory(L"fonts\\", &add_font_from_dir, 1);
	
	g_selected_font = 0;
	if (update_selected_font) for (uint32 i = 0; i < g_fonts.length(); ++i) {
		if (!strcmp(current_font.name, g_fonts[i].name)) {
			g_selected_font = i;
			break;
		}
	}
}

void set_default_theme() {
	g_theme_colors[THEME_COLOR_PLAYING_INDICATOR] = ImVec4{1, 0.6f, 0, 0.8f};
	g_theme_colors[THEME_COLOR_SEEK_BAR] = ImGui::GetStyleColorVec4(ImGuiCol_Header);
	g_theme_colors[THEME_COLOR_SEEK_BAR_BG] = ImGui::GetStyleColorVec4(ImGuiCol_FrameBg);
	refresh_themes();
	refresh_fonts();
}

static uint32 get_theme_index(const char *name) {
	for (uint32 i = 0; i < g_themes.length(); ++i) {
		if (!strcmp(g_themes[i].name, name)) return i;
	}
	return UINT32_MAX;
}

void load_theme(const char *name) {
	ImGuiStyle& style = ImGui::GetStyle();
	refresh_themes();
	refresh_fonts();
	g_selected_theme = get_theme_index(name);
	
	if (g_selected_theme == UINT32_MAX) {
		g_selected_theme = 0;
		log_debug("Couldn't find theme \"%s\"\n", name);
		return;
	}
	
	style = ImGuiStyle();
	ImGui::StyleColorsDark();
	
	char path[256];
	snprintf(path, 256, "themes\\%s.ini", name);
	load_background_image(NULL); // Unload current background image
	ini_parse(path, &theme_ini_handler, NULL);
	
	style.SeparatorTextBorderSize = 1.f;
	
	const char *font = get_font();
	for (uint32 i = 0; i < g_fonts.length(); ++i) {
		if (!strcmp(g_fonts[i].name, font)) {
			g_selected_font = i;
			break;
		}
	}
}

void save_theme(const char *name) {
	char path[256];
	
	g_selected_theme = get_theme_index(name);
	if (g_selected_theme == UINT32_MAX) {
		Theme new_theme = {};
		strncpy(new_theme.name, name, MAX_THEME_NAME_LENGTH);
		g_selected_theme = g_themes.append(new_theme);
	}
	
	const Theme& theme = g_themes[g_selected_theme];
	ImGuiStyle& style = ImGui::GetStyle();
	
	snprintf(path, 256, "themes\\%s.ini", theme.name);
	
	FILE *file = fopen(path, "w");
	if (!file) return;
	
	fprintf(file, "[Colors]\n");
	for (uint32 i = 0; i < ARRAY_LENGTH(g_color_info); ++i) {
		const Color_Info& info = g_color_info[i];
		uint32 color;
		
		if (info.color < ImGuiCol_COUNT) color = ImGui::GetColorU32(style.Colors[info.color]);
		else color = ImGui::GetColorU32(g_theme_colors[info.color - ImGuiCol_COUNT]);
		
		color = flip_endian(color);
		fprintf(file, "%s = %x\n", info.ini_name, color);
	}
	
	const char *background_path = get_background_image_path();
	fprintf(file, "[Style]\n");
	if (background_path) fprintf(file, "BackgroundImage= %s\n", background_path);
	fprintf(file, "Font = %s\n", get_font());
	fprintf(file, "FontSize = %d\n", get_font_size());
	fprintf(file, "IconFontSize = %d\n", get_icon_font_size());
	fprintf(file, "WindowPaddingX = %d\n", (int)style.WindowPadding.x);
	fprintf(file, "WindowPaddingY = %d\n", (int)style.WindowPadding.y);
	fprintf(file, "WindowBorderSize = %d\n", (int)style.WindowBorderSize);
	fprintf(file, "CellPaddingX = %d\n", (int)style.CellPadding.x);
	fprintf(file, "CellPaddingY = %d\n", (int)style.CellPadding.y);
	fprintf(file, "FrameRounding = %d\n", (int)style.FrameRounding);
	fprintf(file, "FramePaddingX = %d\n", (int)style.FramePadding.x);
	fprintf(file, "FramePaddingY = %d\n", (int)style.FramePadding.y);
	fprintf(file, "ItemSpacingX = %d\n", (int)style.ItemSpacing.x);
	fprintf(file, "ItemSpacingY = %d\n", (int)style.ItemSpacing.y);
	fprintf(file, "ScrollbarSize = %d\n", (int)style.ScrollbarSize);
	fprintf(file, "ScrollbarRounding = %d\n", (int)style.ScrollbarRounding);
	fprintf(file, "WindowTitleAlign = %f\n", style.WindowTitleAlign.x);
	
	fclose(file);
}

static bool set_background_image(const char *path) {
	load_background_image(path);
	return true;
}

static inline float clamp(float x, float min, float max) {
	return (x < min) ? min : ((x > max) ? max : x);
}

static inline bool editor_padding_helper(const char *text, ImVec2* val, float min, float max) {
	if (ImGui::InputFloat(text, &val->x, 1.f, 1.f, "%.0f")) {
		val->y = val->x = clamp(val->x, min, max);
		return true;
	}
	return false;
}

static inline bool editor_padding_helper2(const char *text, ImVec2 *val, float min, float max) {
	if (ImGui::InputFloat2(text, &val->x, "%.0f")) {
		val->x = clamp(val->x, min, max);
		val->y = clamp(val->y, min, max);
		return true;
	}
	return false;
}

static inline bool input_float_clamped(const char *text, float *val, float min, float max) {
	if (ImGui::InputFloat(text, val, 1.f, 1.f, "%.0f")) {
		*val = clamp(*val, min, max);
		return true;
	}
	return false;
}

bool show_theme_editor_gui() {
	ImGuiStyle& style = ImGui::GetStyle();
	static char theme_name[MAX_THEME_NAME_LENGTH];
	//static const char *editing_theme;
	static bool new_theme = false;
	static bool dirty = false;
	
	if (ImGui::InputText("Name", theme_name, MAX_THEME_NAME_LENGTH)) new_theme = true;
	
	if (!new_theme) {
		const char *editing_theme = get_loaded_theme();
		if (editing_theme) {
			strcpy(theme_name, editing_theme);
		}
	} else dirty = true;
	
	ImGui::SameLine();
	if (ImGui::BeginCombo("##select_theme", "", ImGuiComboFlags_NoPreview)) {
		const char *sel = show_theme_selector_gui();
		if (sel) {
			load_theme(sel);
			strcpy(theme_name, sel);
			new_theme = false;
			dirty = false;
		}
		
		ImGui::EndCombo();
	}
	
	ImGui::SameLine();
	if (ImGui::Button("Save")) {
		if (theme_name[0]) {
			save_theme(theme_name);
			dirty = false;
		}
		else {
			ImGui::OpenPopup("##warning_popup");
		}
	}
	
	ImGui::SameLine();
	if (ImGui::Button("Load")) {
		load_theme(theme_name);
	}
	
	if (ImGui::BeginPopup("##warning_popup")) {
		ImGui::TextUnformatted("Cannot save theme without a name");
		if (ImGui::Button("Ok")) ImGui::CloseCurrentPopup();
		ImGui::EndPopup();
	}
	
	ImGui::SeparatorText("Colors");
	
	for (uint32 icolor = 0; icolor < ARRAY_LENGTH(g_color_info); ++icolor) {
		const Color_Info& info = g_color_info[icolor];
		if (info.color < ImGuiCol_COUNT) {
			ImVec4 color = ImGui::GetStyleColorVec4(info.color);
			if (ImGui::ColorEdit4(info.name, &color.x)) {
				style.Colors[info.color] = color;
				dirty = true;
			}
		}
		else {
			dirty |= ImGui::ColorEdit4(info.name, &g_theme_colors[info.color - ImGuiCol_COUNT].x);
		}
	}
	
	const char *background_path = get_background_image_path();
	ImGui::SeparatorText("Style");
	
	if (ImGui::BeginTable("##style_table", 2)) {
		ImGui::TableNextRow();
		ImGui::TableNextColumn();
		dirty |= input_float_clamped("Border Size", &style.WindowBorderSize, 0.f, 8.f);
		ImGui::TableNextColumn();
		dirty |= editor_padding_helper2("Table Cell Padding", &style.CellPadding, 0.f, 8.f);
		
		ImGui::TableNextRow();
		ImGui::TableNextColumn();
		dirty |= ImGui::SliderFloat("Frame Rounding", &style.FrameRounding, 0.f, 16.f, "%.0f");
		ImGui::TableNextColumn();
		dirty |= editor_padding_helper2("Frame Padding", &style.FramePadding, 0.f, 8.f);
				
		ImGui::TableNextRow();
		ImGui::TableNextColumn();
		dirty |= editor_padding_helper2("Item Spacing", &style.ItemSpacing, 0.f, 8.f);
		ImGui::TableNextColumn();
		dirty |= ImGui::SliderFloat("Title Alignment", &style.WindowTitleAlign.x, 0.f, 1.f);
		
		ImGui::TableNextRow();
		ImGui::TableNextColumn();
		dirty |= ImGui::SliderFloat("Scrollbar Rounding", &style.ScrollbarRounding, 0.f, 16.f, "%.0f");
		ImGui::TableNextColumn();
		dirty |= input_float_clamped("Scrollbar Size", &style.ScrollbarSize, 8.f, 32.f);
		
		ImGui::EndTable();
	}
	
	ImGui::TextUnformatted("Background image");
	ImGui::SameLine();
	if (ImGui::Button("Browse")) {
		for_each_file_from_dialog(&set_background_image, FILE_DATA_TYPE_IMAGE, false);
	}
	ImGui::SameLine();
	if (ImGui::Button("Remove")) {
		load_background_image(NULL);
		dirty = true;
	}
	ImGui::TextUnformatted(background_path ? background_path : "<none>");
	
	if (ImGui::BeginCombo("Font", g_fonts.length() ? g_fonts[g_selected_font].name : "<none>")) {
		for (uint32 i = 0; i < g_fonts.length(); ++i) {
			if (ImGui::Selectable(g_fonts[i].name)) {
				g_selected_font = i;
				set_font(g_fonts[i].name);
			}
		}
		ImGui::EndCombo();
	}
	ImGui::SameLine();
	if (ImGui::Button("Refresh")) refresh_fonts();
	
	int font_size = get_font_size();
	if (ImGui::InputInt("Font size", &font_size)) {
		set_font_size(font_size);
		dirty = true;
	}
	
	int icon_size = get_icon_font_size();
	if (ImGui::InputInt("Icon size", &icon_size)) {
		set_icon_font_size(icon_size);
		dirty = true;
	}
	
	return dirty;
}

uint32 get_theme_color(Theme_Color color) {
	uint32 c = ImGui::GetColorU32(g_theme_colors[color]);
	return c ? c : 0xff000000;
}

const char *show_theme_selector_gui() {
	for (uint32 i = 0; i < g_themes.length(); ++i) {
		if (ImGui::Selectable(g_themes[i].name)) {
			return g_themes[i].name;
		}
	}
	
	return NULL;
}

const char *get_loaded_theme() {
	return g_themes.length() ? g_themes[g_selected_theme].name : NULL;
}