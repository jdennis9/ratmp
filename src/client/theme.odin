/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
package client

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:encoding/json"
import "core:os/os2"
import "core:strings"
import "core:path/filepath"

import imgui "src:thirdparty/odin-imgui"

import "src:util"

Theme_Custom_Color :: enum {
	PlayingHighlight,
	PeakQuiet,
	PeakLoud,
}

Theme :: struct {
	imgui_colors: [imgui.Col][4]f32,
	custom_colors: [Theme_Custom_Color][4]f32,
	gen_params: Theme_Gen_Params,
}

Theme_Gen_Color :: enum {
	Text,
	FgPrimary,
	FgSecondary,
	BgPrimary,
	BgSecondary,
}

Theme_Gen_Params :: struct {
	colors: [Theme_Gen_Color][3]f32,
	brightness_offset: f32,
}

@(private="file")
_CUSTOM_COLOR_NAMES := [Theme_Custom_Color]cstring {
	.PlayingHighlight = "Playing highlight",
	.PeakQuiet = "Peak quiet",
	.PeakLoud = "Peak loud",
}

theme_set_defaults :: proc(theme: ^Theme) {
	style := imgui.GetStyle()
	for col, i in style.Colors {
		theme.imgui_colors[auto_cast i] = col
	}

	theme.custom_colors[.PlayingHighlight] = {1, 0.576, 0.227, 0.9}
	theme.custom_colors[.PeakQuiet] = {0.5, 0.5, 0.5, 0.9}
	theme.custom_colors[.PeakLoud] = {0.1, 1, 0.1, 1}
}

theme_generate :: proc(theme: ^Theme, params: Theme_Gen_Params) {
	HSV :: [3]f32

	Color_Params :: struct {
		base: Theme_Gen_Color,
		hsv: HSV,
	}

	color_map: map[imgui.Col]Color_Params
	defer delete(color_map)
	color_map[.TitleBgActive] = {.FgPrimary, {1, 0.8, 0.3}}

	color_map[.Button] = {.FgPrimary, {1, 1, 1}}
	color_map[.ButtonHovered] = {.FgPrimary, {1, 0.9, 1}}
	color_map[.ButtonActive] = {.FgPrimary, {1, 1.2, 0.9}}

	color_map[.FrameBg] = {.FgPrimary, {1, 0.8, 0.5}}
	color_map[.FrameBgHovered] = {.FgPrimary, {1, 0.6, 0.9}}
	color_map[.FrameBgActive] = {.FgPrimary, {1, 0.6, 0.9}}

	color_map[.Header] = {.FgPrimary, {1, 0.9, 0.9}}
	color_map[.HeaderHovered] = {.FgPrimary, {1, 0.8, 1.1}}
	color_map[.HeaderActive] = {.FgPrimary, {1, 0.8, 1.0}}

	color_map[.TabHovered] = {.FgPrimary, {1, 0.8, 0.8}}
	color_map[.Tab] = {.FgPrimary, {1, 0.6, 0.5}}
	color_map[.TabSelected] = {.FgPrimary, {1, 0.8, 0.6}}
	color_map[.TabSelectedOverline] = {.FgSecondary, {1, 1, 1}}
	color_map[.TabDimmed] = {.FgPrimary, {1, 0.6, 0.3}}
	color_map[.TabDimmedSelected] = {.FgPrimary, {1, 0.6, 0.5}}
	color_map[.TabDimmedSelectedOverline] = {.FgPrimary, {1, 0, 0.7}}

	color_map[.SliderGrab] = {.FgPrimary, {1, 0.8, 0.8}}
	color_map[.SliderGrabActive] = {.FgPrimary, {1, 0.8, 0.9}}

	color_map[.DockingPreview] = {.FgPrimary, {1, 1.1, 1.1}}

	color_map[.TableBorderStrong] = {.FgSecondary, {1, 1, 0.8}}
	color_map[.TableBorderLight] = {.FgSecondary, {1, 0.8, 0.8}}
	
	color_map[.CheckMark] = {.FgPrimary, {1, 1, 1.1}}

	color_map[.ResizeGrip] = {.FgPrimary, {1, 1, 0.9}}
	color_map[.ResizeGripHovered] = {.FgPrimary, {1, 1, 0.9}}
	color_map[.ResizeGripActive] = {.FgPrimary, {1, 1, 0.9}}

	color_map[.SeparatorHovered] = {.FgPrimary, {1, 1, 0.6}}
	color_map[.SeparatorActive] = {.FgPrimary, {1, 1, 0.6}}

	color_map[.NavCursor] = {.FgPrimary, {1, 1, 1.1}}

	for _, &value in color_map {
		value.hsv[2] *= (1 + params.brightness_offset)
	}

	rgb_to_hsv :: proc(v: [3]f32) -> (hsv: HSV) {
		imgui.ColorConvertRGBtoHSV(v.r, v.g, v.b, &hsv[0], &hsv[1], &hsv[2])
		return
	}

	hsv_to_rgb :: proc(v: HSV) -> (rgb: [3]f32) {
		imgui.ColorConvertHSVtoRGB(v[0], v[1], v[2], &rgb.r, &rgb.g, &rgb.b)
		return
	}

	
	base_hsvs: [Theme_Gen_Color][3]f32
	for col in Theme_Gen_Color {
		base_hsvs[col] = rgb_to_hsv(params.colors[col])
	}

	style := imgui.GetStyle()

	for col in imgui.Col {
		if col == .COUNT {break}
		color_info := color_map[col] or_continue
		base := rgb_to_hsv(params.colors[color_info.base])
		hsv := base * color_info.hsv
		style.Colors[col].xyz = hsv_to_rgb(hsv)
		theme.imgui_colors[col] = style.Colors[col]
	}
}

set_theme :: proc(client: ^Client, theme: Theme, name: string) {
	style := imgui.GetStyle()

	for &col, i in style.Colors {
		col = theme.imgui_colors[auto_cast i]
	}

	global_theme = theme
	util.copy_string_to_buf(client.settings.theme[:], name)
}

theme_save_to_file :: proc(theme: Theme, path: string) -> (ok: bool) {
	if os2.exists(path) {
		os2.remove(path)
	}

	file, file_error := os2.create(path)
	if file_error != nil {return}
	defer os2.close(file)

	data, marshal_error := json.marshal(theme, {pretty = true})
	if marshal_error != nil {return}
	defer delete(data)

	os2.write(file, data)

	return true
}

theme_load_from_file :: proc(theme: ^Theme, path: string) -> (loaded: bool) {
	theme_set_defaults(theme)

	data, read_error := os2.read_entire_file_from_path(path, context.allocator)
	if read_error != nil {return}
	defer delete(data)

	unmarshal_error := json.unmarshal(data, theme)
	if unmarshal_error != nil {
		log.error(unmarshal_error)
		return
	}

	return true
}

theme_save_from_name :: proc(client: Client, theme: Theme, name: string) -> (saved: bool) {
	path := theme_path_from_name(client, name, context.allocator)
	defer delete(path)
	log.debug(path)
	return theme_save_to_file(theme, path)
}

theme_load_from_name :: proc(client: Client, theme: ^Theme, name: string) -> (loaded: bool) {
	path := theme_path_from_name(client, name, context.allocator)
	defer delete(path)
	return theme_load_from_file(theme, path)
}

theme_path_from_name :: proc(client: Client, name: string, allocator: runtime.Allocator) -> string {
	with_extension := fmt.aprint(name, ".json", sep="", allocator = allocator)
	defer delete(with_extension)
	return filepath.join({client.paths.theme_folder, with_extension}, allocator)
}

theme_delete_from_name :: proc(client: ^Client, name: string) {
	path := theme_path_from_name(client^, name, context.allocator)
	defer delete(path)
	os2.remove(path)
}

@private
theme_scan_folder :: proc(client: ^Client) {
	if !os2.exists(client.paths.theme_folder) {
		os2.make_directory_all(client.paths.theme_folder)
	}

	for theme in client.theme_names {
		delete(theme)
	}
	clear(&client.theme_names)

	files, read_error := os2.read_all_directory_by_path(client.paths.theme_folder, context.allocator)
	if read_error != nil {
		log.error(read_error)
		return
	}
	defer os2.file_info_slice_delete(files, context.allocator)

	for file in files {
		name := filepath.stem(filepath.base(file.fullpath))
		append(&client.theme_names, strings.clone_to_cstring(name))
	}
}

@private
themes_init :: proc(client: ^Client) {
	theme_scan_folder(client)
}

@private
themes_destroy :: proc(client: ^Client) {
	for name in client.theme_names {delete(name)}
	delete(client.theme_names)
}

Theme_Editor_State :: struct {
	new_theme_name: [64]u8,
	name_error: [64]u8,
}

global_theme: Theme

@private
theme_editor_show :: proc(client: ^Client, state: ^Theme_Editor_State) -> (changes: bool) {
	popup_name: cstring = "New theme name"
	popup_id := imgui.GetID(popup_name)
	style := imgui.GetStyle()
	current_theme_name := cstring(&client.settings.theme[0])
	theme := &global_theme

	if imgui.BeginCombo("##select_theme", current_theme_name) {
		for theme_name in client.theme_names {
			if imgui.MenuItem(theme_name) {
				theme_load_from_name(client^, theme, string(theme_name))
				set_theme(client, theme^, string(theme_name))
				changes = true
			}
		}

		imgui.EndCombo()
	}

	// Name theme popup
	if imgui.BeginPopupModal(popup_name) {
		commit: bool
		name := cstring(raw_data(state.new_theme_name[:]))

		imgui.TextUnformatted("Theme name")

		if imgui.InputText("##name", name, auto_cast len(state.new_theme_name), {.EnterReturnsTrue}) {
			commit = true
		}

		commit |= imgui.Button("Save")
		imgui.SameLine()
		if imgui.Button("Cancel") {imgui.CloseCurrentPopup()}

		if state.name_error[0] != 0 {
			imgui.Text(cstring(raw_data(state.name_error[:])))
		}

		if commit {
			if len(name) == 0 {
				util.copy_string_to_buf(state.name_error[:], "Name cannot be empty")
			}
			else {
				theme_save_from_name(client^, theme^, string(name))
				set_theme(client, theme^, string(name))
				themes_init(client)
				imgui.CloseCurrentPopup()
				for &s in state.name_error {s = 0}
				for &s in state.new_theme_name {s = 0}
			}
		}

		imgui.EndPopup()
	}

	imgui.SameLine()
	if imgui.Button("Refresh themes") {
		themes_init(client)
	}

	if imgui.Button("New") {
		imgui.OpenPopupID(popup_id)
	}
	imgui.SameLine()

	imgui.BeginDisabled(len(current_theme_name) == 0)
	if imgui.Button("Save") {
		theme_save_from_name(client^, theme^, string(current_theme_name))
	}
	imgui.EndDisabled()

	imgui.SameLine()
	if imgui.Button("Load") {
		theme_load_from_name(client^, theme, string(current_theme_name))
		set_theme(client, theme^, string(current_theme_name))
	}

	imgui.SameLine()
	if imgui.Button("Delete") {
		theme_delete_from_name(client, string(current_theme_name))
		theme_scan_folder(client)
		if len(client.theme_names) > 0 {
			theme_load_from_name(client^, theme, string(client.theme_names[0]))
			set_theme(client, theme^, string(client.theme_names[0]))
		}
		else {
			for &c in client.settings.theme {c = 0}
		}
	}

	for col in Theme_Custom_Color {
		changes |= imgui.ColorEdit4(_CUSTOM_COLOR_NAMES[col], &theme.custom_colors[col])
	}

	imgui.SeparatorText("Quick Edit")
	{
		gen: bool
		gen |= imgui.ColorEdit3("Fg. Primary", &theme.gen_params.colors[.FgPrimary])
		gen |= imgui.ColorEdit3("Fg. Secondary", &theme.gen_params.colors[.FgSecondary])
		gen |= imgui.SliderFloat("Brightness", &theme.gen_params.brightness_offset, -1, 1)
		if imgui.ColorEdit4("Window background", &style.Colors[imgui.Col.WindowBg]) {
			theme.imgui_colors[.WindowBg] = style.Colors[imgui.Col.WindowBg]
		}
		if imgui.ColorEdit4("Text", &style.Colors[imgui.Col.Text]) {
			theme.imgui_colors[.Text] = style.Colors[imgui.Col.Text]
		}
		if gen {
			theme_generate(theme, theme.gen_params)
		}
	}

	if imgui.CollapsingHeader("Fine Tune") {
		for &col, index in style.Colors {
			if imgui.ColorEdit4(imgui.GetStyleColorName(auto_cast index), &col) {
				theme.imgui_colors[auto_cast index] = col
				changes = true
			}
		}
	}

	return
}
