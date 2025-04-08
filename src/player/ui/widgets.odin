/*
	RAT MP: A lightweight graphical music player
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
package ui;

import glm "core:math/linalg/glsl";

import imgui "../../libs/odin-imgui";

import "../analysis";

lerp :: glm.lerp_f32;

@private
_show_scrubber_widget :: proc(str_id: cstring, p_value: ^f32, min, max: f32, size_arg: imgui.Vec2 = {}) -> bool {
	size := size_arg;
	draw_list := imgui.GetWindowDrawList();
	available_size := imgui.GetContentRegionAvail();
	cursor := imgui.GetCursorScreenPos();
	mouse := imgui.GetMousePos();
	frac := (p_value^ - min) / (max - min);
	style := imgui.GetStyle();

	if size.x <= 0 {size.x = available_size.x - style.WindowPadding.x;}
	if size.y <= 0 {size.y = imgui.GetTextLineHeight();}

	clickbox_size := imgui.Vec2{
		size.x + (style.FramePadding.x*2),
		size.y + (style.FramePadding.y*2),
	};
	bg_pos := imgui.Vec2{cursor.x, cursor.y + style.FramePadding.y + (size.y*0.25),};

	imgui.InvisibleButton(str_id, clickbox_size);

	if imgui.IsItemActive() || imgui.IsItemDeactivated() {
		frac = clamp((mouse.x - cursor.x) / size.x, 0.0, 1.0);
	}

	// Background rect
	imgui.DrawList_AddRectFilled(
		draw_list,
		bg_pos,
		{bg_pos.x + size.x, bg_pos.y + (size.y*0.5)},
		imgui.GetColorU32ImVec4(style.Colors[imgui.Col.Header]),
		4
	);
	// Foreground rect
	imgui.DrawList_AddRectFilled(
		draw_list,
		bg_pos,
		{bg_pos.x + (size.x*frac), bg_pos.y + (size.y*0.5)},
		imgui.GetColorU32ImVec4(style.Colors[imgui.Col.HeaderActive]),
		4
	);
	// Handle
	imgui.DrawList_AddCircleFilled(
		draw_list,
		{bg_pos.x + (size.x * frac), bg_pos.y + (size.y*0.25)},
		size.y * 0.5,
		imgui.GetColorU32ImVec4(style.Colors[imgui.Col.HeaderActive]),
	);

	if imgui.IsItemDeactivated() {
		frac = clamp((mouse.x - cursor.x) / size.x, 0.0, 1.0);
		p_value^ = lerp(min, max, frac);
		return true;
	}

	return false;
}

@private
_show_peak_meter_widget :: proc(str_id: cstring, req_size: [2]f32) {
	drawlist := imgui.GetWindowDrawList();
	avail_size := imgui.GetContentRegionAvail();
	cursor := imgui.GetCursorScreenPos();
	style := imgui.GetStyle();
	size := req_size;

	peaks := analysis.get_channel_peaks();
	channels := len(peaks);

	if channels == 0 {return}

	if size.y == 0 {
		size.y = avail_size.y + style.FramePadding.y;
	}

	bar_height := (size.y / f32(channels)) - 1;
	y_offset: f32 = style.FramePadding.y;
	color := imgui.GetColorU32(.PlotHistogram);

	for &peak in peaks {
		peak = clamp(peak, 0, 1);
		pmin := [2]f32{cursor.x, cursor.y + y_offset};
		pmax := [2]f32{pmin.x + size.x*peak, pmin.y + bar_height};
		imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, color);
		y_offset += bar_height + 1;
	}

	imgui.InvisibleButton(str_id, size);
}

@private
_show_bars_widget :: proc(str_id: cstring, values: []f32, minval, maxval: f32, req_size: [2]f32 = {0, 0}) {
	drawlist := imgui.GetWindowDrawList();
	avail_size := imgui.GetContentRegionAvail();

	size := [2]f32{
		req_size.x == 0 ? avail_size.x : req_size.x,
		req_size.y == 0 ? avail_size.y : req_size.y,
	};

	max_bar_height := size.y;

	for value, index in values {
		
	}
}
