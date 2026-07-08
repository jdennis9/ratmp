/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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
#+private file
package client

import "core:mem"
import "core:log"
import "core:encoding/json"
import "core:strings"
import "core:os"
import "src:main/shared"
import "core:path/filepath"
import "core:math/rand"
import "src:imx"
import imgui "src:thirdparty/odin-imgui"

@private
Theme_Color :: enum {
	PlayingHighlight,
	LeftChannelWave,
	RightChannelWave,
	VolumeLow,
	VolumeHigh,
	WaveBarInner,
	WaveBarOuter,
}

THEME_COLOR_NAMES := [Theme_Color]cstring {
	.PlayingHighlight = "Playing highlight",
	.LeftChannelWave  = "Oscilloscope left channel",
	.RightChannelWave = "Oscilloscope right channel",
	.VolumeLow        = "Peak low volume",
	.VolumeHigh       = "Peak high volume",
	.WaveBarInner     = "Wave bar quiet",
	.WaveBarOuter     = "Wave bar loud",
}

@private
Theme_Accent :: enum {
	Fg1,
}

// Model for theme .json file
_Theme_Model :: struct {
	name:          string,
	accents:       [Theme_Accent][3]f32,
	imgui_colors:  [imgui.Col]u32,
	colors:        [Theme_Color]u32,
	locked_colors: []imgui.Col,
	frame_borders: bool,
}

// The current theme
_theme: struct {
	accents:              [Theme_Accent][3]f32,
	colors:               [Theme_Color]u32,
	color_locked:         [imgui.Col]bool, // prevent accents from modifying the color
	path:                 string,
	name:                 string,
	dirty:                bool,
	enable_frame_borders: bool,
}

_Avail_Theme :: struct {
	name: string,
	path: string,
}

_themes: struct {
	dir:                string,
	avail_themes_arena: mem.Dynamic_Arena,
	avail_themes:       [dynamic]_Avail_Theme,
	serial:             uint,
}

_THEME_FILENAME_TEMPLATE :: "*.json"

@private
theme_init :: proc() -> shared.Error {
	_set_colors_to_default()

	_themes.dir = filepath.join({get_config_path(), "themes"}, context.allocator) or_return

	mem.dynamic_arena_init(&_themes.avail_themes_arena, block_size=4<<10)

	refresh_themes_folder()

	return nil
}

@private
theme_shutdown :: proc() {
	mem.dynamic_arena_destroy(&_themes.avail_themes_arena)
	delete(_themes.dir)
	delete(_themes.avail_themes)
}

@private
refresh_themes_folder :: proc() -> shared.Error {
	frame_allocator_guard()

	mem.dynamic_arena_free_all(&_themes.avail_themes_arena)
	clear(&_themes.avail_themes)

	allocator := mem.dynamic_arena_allocator(&_themes.avail_themes_arena)

	files := os.read_all_directory_by_path(_themes.dir, context.allocator) or_return
	defer os.file_info_slice_delete(files, context.allocator)

	for file in files {
		model: _Theme_Model
		data := os.read_entire_file_from_path(file.fullpath, context.allocator) or_continue
		defer delete(data)

		json.unmarshal(data, &model, allocator=get_frame_allocator())

		append(&_themes.avail_themes, _Avail_Theme {
			name = strings.clone(model.name, allocator),
			path = strings.clone(file.fullpath, allocator),
		})
	}

	return nil
}

@private
set_theme_from_name :: proc(name: string) -> shared.Error {
	theme_path := ""
	
	for at in _themes.avail_themes {
		if at.name == name {
			theme_path = at.path
		}
	}
	
	if theme_path == "" do return shared.Error_Code.NotFound

	return set_theme_from_file(theme_path)
}

@private
set_theme_from_file :: proc(path: string) -> shared.Error {
	frame_allocator_guard()
	
	data := os.read_entire_file_from_path(path, context.allocator) or_return
	defer delete(data)
	
	model: _Theme_Model
	unmarshal_error := json.unmarshal(data, &model, allocator=get_frame_allocator())
	
	if unmarshal_error != nil {
		log.error(unmarshal_error)
		return false
	}
	
	delete(_theme.path)
	
	_theme.accents = model.accents
	_theme.colors  = model.colors
	_theme.dirty   = false
	_theme.path    = strings.clone(path)
	_set_theme_name(model.name)

	_theme.color_locked = {}
	
	for col in model.locked_colors {
		_theme.color_locked[col] = true
	}
	
	style := imgui.GetStyle()
	for col, idx in model.imgui_colors {
		if idx == .COUNT do break
		style.Colors[idx] = imgui.ColorConvertU32ToFloat4(col)
	}

	_themes.serial += 1
	
	return nil
}

@private
refresh_theme :: proc() {
	if _theme.path == "" do return
	set_theme_from_file(_theme.path)
}

@private
is_theme_dirty :: proc() -> bool {
	return _theme.dirty
}

@private
get_theme_color :: proc(col: Theme_Color) -> u32 {
	return _theme.colors[col]
}

_set_colors_to_default :: proc() {
	_theme.colors[.PlayingHighlight] = 0xff0568fc
	_theme.colors[.LeftChannelWave]  = 0xffffffff
	_theme.colors[.RightChannelWave] = 0xff00ffff
	_theme.colors[.VolumeLow]        = 0xff00ff00
	_theme.colors[.VolumeHigh]       = 0xff0000ff
	_theme.colors[.WaveBarOuter]     = 0xffffce00
	_theme.colors[.WaveBarInner]     = 0xffff0800
}

_set_theme_name :: proc(name: string) {
	delete(_theme.name)
	_theme.name = strings.clone(name)
}

_new_theme :: proc() {
	delete(_theme.path)
	_theme.path = ""
}

_save_theme :: proc() -> shared.Error {
	file:               ^os.File
	model:              _Theme_Model
	locked_color_count: int

	frame_allocator_guard()

	temp_allocator := get_frame_allocator()
	style          := imgui.GetStyle()
	t              := &_theme
	
	opt := json.Marshal_Options {
		use_enum_names = true,
	}
	
	if t.path == "" {
		file = os.create_temp_file(_themes.dir, _THEME_FILENAME_TEMPLATE) or_return
		t.path = strings.clone(os.name(file))
	}
	else {
		file = os.create(t.path) or_return
	}
	
	defer os.close(file)
	
	model.name    = t.name
	model.accents = t.accents
	model.colors  = t.colors
	
	for col in imgui.Col {
		if col == .COUNT do break
		model.imgui_colors[col] = imgui.GetColorU32ImVec4(style.Colors[col])
		if t.color_locked[col] do locked_color_count += 1
	}
	
	if locked_color_count > 0 {
		model.locked_colors = make([]imgui.Col, locked_color_count, temp_allocator)
		c := 0
		for col in imgui.Col {
			if col == .COUNT do break
			if t.color_locked[col] {
				model.locked_colors[c] = col
				c += 1
			}
		}
	}
	
	marshal_error := json.marshal_to_writer(os.to_writer(file), model, &opt)
	if marshal_error != nil {
		log.error(marshal_error)
		return false
	}

	t.dirty = false

	refresh_themes_folder()
	
	return nil
}

@private
show_theme_selector_menu_items :: proc() -> bool {
	frame_allocator_guard()
	allocator := get_frame_allocator()
	changed := false

	for at, i in _themes.avail_themes {
		imgui.PushIDInt(auto_cast i)
		defer imgui.PopID()

		if imgui.MenuItem(strings.clone_to_cstring(at.name, allocator)) {
			changed |= set_theme_from_file(at.path) == nil
		}
	}

	return changed
}

@private
show_theme_editor :: proc() -> bool {
	@static w: struct {
		name_buf:    [128]u8,
		name_serial: uint,
	}

	t := &_theme

	edit_imgui_col :: proc(label: cstring, style: ^imgui.Style, idx: imgui.Col) -> (edited: bool) {
		imgui.PushIDInt(auto_cast idx)
		defer imgui.PopID()

		col := &style.Colors[idx]

		if imgui.Button(ICON_DICE) {
			_theme.color_locked[idx] = true
			edited = true
			col.r = rand.float32()
			col.g = rand.float32()
			col.b = rand.float32()
		}

		imgui.SameLine()

		edited |= imgui.Checkbox("##locked", &_theme.color_locked[idx])

		imgui.SameLine()

		if imgui.ColorEdit4(label, col, {.NoInputs}) {
			edited = true
			_theme.color_locked[idx] = true
		}

		return
	}

	edit_accent :: proc(label: cstring, accent: Theme_Accent) -> (edited: bool) {
		imgui.PushID(label)
		defer imgui.PopID()

		if imgui.Button(ICON_DICE) {
			edited = true
			_theme.accents[accent].r = rand.float32()
			_theme.accents[accent].g = rand.float32()
			_theme.accents[accent].b = rand.float32()
		}

		imgui.SameLine()

		edited |= imgui.ColorEdit3(label, &_theme.accents[accent], {.NoInputs})

		return
	}
	
	changed:        bool
	accent_changed: bool

	style := imgui.GetStyle()

	// Update name if needed
	if w.name_serial != _themes.serial {
		w.name_serial = _themes.serial
		w.name_buf = {}
		copy(w.name_buf[:len(w.name_buf)-1], _theme.name)
	}

	if imgui.InputText("Name", cstring(&w.name_buf[0]), auto_cast len(w.name_buf)) {
		_set_theme_name(shared.string_from_array(w.name_buf[:]))
	}

	// Select existing theme
	imgui.SameLine()
	if imgui.BeginCombo("##select_theme", nil, {.NoPreview}) {
		defer imgui.EndCombo()

		show_theme_selector_menu_items()
	}

	if imgui.Button("Save") {
		_save_theme()
	}
	
	imgui.SameLine()
	if imgui.Button("Reload") {
		refresh_theme()
	}

	imgui.SameLine()
	if imgui.Button("New") {
		_new_theme()
	}

	if t.path == "" {
		imgui.SameLine()
		imgui.TextDisabled("[Not saved]")
	}

	imgui.SeparatorText("Quick Edit")
	imgui.PushID("quickedit")

	changed |= imgui.Checkbox("Frame borders", &t.enable_frame_borders)

	accent_changed |= edit_accent("Accent", .Fg1)
	changed |= edit_imgui_col("Text",                    style, .Text)
	changed |= edit_imgui_col("Table borders",           style, .TableBorderLight)
	changed |= edit_imgui_col("Table headers",           style, .TableHeaderBg)
	changed |= edit_imgui_col("Table header underline",  style, .TableBorderStrong)
	changed |= edit_imgui_col("Table background",        style, .TableRowBg)
	changed |= edit_imgui_col("Table alt background",    style, .TableRowBgAlt)
	changed |= edit_imgui_col("Borders",                 style, .Border)
	changed |= edit_imgui_col("Window background",       style, .WindowBg)
	changed |= edit_imgui_col("Frame background",        style, .FrameBg)
	changed |= edit_imgui_col("Menu bar",                style, .MenuBarBg)

	imgui.PopID()

	imgui.SeparatorText("Main")
	imgui.PushID("main")

	for col in Theme_Color {
		imgui.PushIDInt(1000 + auto_cast col)
		defer imgui.PopID()

		if imgui.Button(ICON_DICE) {
			changed = true
			vec := imgui.ColorConvertU32ToFloat4(t.colors[col])
			vec.r = rand.float32()
			vec.g = rand.float32()
			vec.b = rand.float32()
			t.colors[col] = imgui.GetColorU32ImVec4(vec)
		}

		imgui.SameLine()

		changed |= imx.color_edit_u32(THEME_COLOR_NAMES[col], &t.colors[col], {.NoInputs})
	}

	imgui.PopID()

	imgui.SeparatorText("Fine Tune")
	imgui.PushID("finetune")

	for col in imgui.Col {
		if col == imgui.Col.COUNT do break
		changed |= edit_imgui_col(imgui.GetStyleColorName(col), style, col)
	}

	imgui.PopID()

	if accent_changed {
		_apply_accents()
	}

	if changed {
		style.FrameBorderSize = t.enable_frame_borders ? 1 : 0
		t.dirty = true
	}

	return true
}

_apply_accents :: proc() {
	rgb_to_hsv :: proc(v: [3]f32) -> (hsv: [3]f32) {
		imgui.ColorConvertRGBtoHSV(v.r, v.g, v.b, &hsv[0], &hsv[1], &hsv[2])
		return
	}

	hsv_to_rgb :: proc(v: [3]f32) -> (rgb: [3]f32) {
		imgui.ColorConvertHSVtoRGB(v[0], v[1], v[2], &rgb.r, &rgb.g, &rgb.b)
		return
	}

	_Accent_Color :: struct {
		base: Maybe(Theme_Accent),
		hsv: [3]f32,
	}

	t := &_theme

	@static color_map: [imgui.Col]_Accent_Color = #partial {
		.Button                    = {.Fg1, {1, 1, 1}},
		.ButtonHovered             = {.Fg1, {1, 0.9, 1}},
		.ButtonActive              = {.Fg1, {1, 1.2, 0.9}},
		.FrameBg                   = {.Fg1, {1, 0.8, 0.5}},
		.FrameBgHovered            = {.Fg1, {1, 0.6, 0.9}},
		.FrameBgActive             = {.Fg1, {1, 0.6, 0.9}},
		.Header                    = {.Fg1, {1, 0.9, 0.9}},
		.HeaderHovered             = {.Fg1, {1, 0.8, 1.1}},
		.HeaderActive              = {.Fg1, {1, 0.8, 1.0}},
		.TabHovered                = {.Fg1, {1, 0.8, 0.8}},
		.Tab                       = {.Fg1, {1, 0.6, 0.5}},
		.TabSelected               = {.Fg1, {1, 0.8, 0.6}},
		.TabSelectedOverline       = {.Fg1, {1, 1, 1}},
		.TabDimmed                 = {.Fg1, {1, 0.6, 0.3}},
		.TabDimmedSelected         = {.Fg1, {1, 0.6, 0.5}},
		.TabDimmedSelectedOverline = {.Fg1, {1, 0, 0.7}},
		.SliderGrab                = {.Fg1, {1, 0.8, 0.8}},
		.SliderGrabActive          = {.Fg1, {1, 0.8, 0.9}},
		.DockingPreview            = {.Fg1, {1, 1.1, 1.1}},
		.CheckMark                 = {.Fg1, {1, 1, 1.1}},
		.ResizeGrip                = {.Fg1, {1, 1, 0.9}},
		.ResizeGripHovered         = {.Fg1, {1, 1, 0.9}},
		.ResizeGripActive          = {.Fg1, {1, 1, 0.9}},
		.SeparatorHovered          = {.Fg1, {1, 1, 0.6}},
		.SeparatorActive           = {.Fg1, {1, 1, 0.6}},
		.TitleBgActive             = {.Fg1, {1, 0.8, 0.2}},
		.NavCursor                 = {.Fg1, {1, 1, 1.1}},
	}

	style := imgui.GetStyle()

	for col in imgui.Col {
		if col == .COUNT do break
		if t.color_locked[col] do continue

		info   := color_map[col]
		accent := info.base.? or_continue
		base   := rgb_to_hsv(t.accents[accent].xyz)
		hsv    := base * info.hsv

		style.Colors[col].xyz = hsv_to_rgb(hsv)
	}
}
