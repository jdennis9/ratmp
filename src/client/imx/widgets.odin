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
package imgui_extensions

import "core:unicode/utf8"
import "core:math/linalg"

import imgui "src:thirdparty/odin-imgui"

lerp :: linalg.lerp

scrubber :: proc(str_id: cstring, p_value: ^f32, min, max: f32, size_arg: imgui.Vec2 = {}, marker_interval: f32 = 10) -> bool {
	size: [2]f32
	style := imgui.GetStyle()
	drawlist := imgui.GetWindowDrawList()
	span := max - min
	frac := (p_value^ + min) / span
	avail_size := imgui.GetContentRegionAvail()
	cursor := imgui.GetCursorScreenPos() + style.FramePadding*1.5
	mouse := imgui.GetMousePos()

	size.x = size_arg.x == 0 ? avail_size.x : size_arg.x
	size.y = size_arg.y == 0 ? avail_size.y : size_arg.y

	size -= style.FramePadding*1.5
	cursor.y += size.y / 4

	if avail_size.x <= 4 || avail_size.y <= 4 {return false}

	// Button
	imgui.InvisibleButton(str_id, avail_size)
	if imgui.IsItemActive() || imgui.IsItemDeactivated() {
		frac = clamp((mouse.x - cursor.x) / size.x, 0.0, 1.0)
	}
	hovered := imgui.IsItemHovered()

	// Bg
	imgui.DrawList_AddRectFilled(drawlist, cursor, cursor + size, imgui.GetColorU32(.Header), 2)
	// Fg
	imgui.DrawList_AddRectFilled(drawlist, cursor, cursor + {size.x * frac, size.y}, imgui.GetColorU32(.HeaderActive), 2)

	// Scrubber
	scrubber_size := [2]f32{size.y*0.8, size.y}
	scrubber_padding := [2]f32{2, 2}

	imgui.DrawList_AddRectFilled(drawlist, 
		{cursor.x + frac * size.x, cursor.y} - scrubber_padding,
		{cursor.x + frac * size.x, cursor.y} + scrubber_padding + scrubber_size,
		hovered ? imgui.GetColorU32(.NavCursor) : imgui.GetColorU32(.HeaderActive),
		2
	)

	if imgui.IsItemDeactivated() {
		frac = clamp((mouse.x - cursor.x) / size.x, 0.0, 1.0)
		p_value^ = lerp(min, max, frac)
		return true
	}

	return false
}

wave_seek_bar :: proc(
	str_id: cstring, peaks: []f32, position: ^f32, length: f32, size_arg := [2]f32{}
) -> (activated: bool) {
	if len(peaks) == 0 {return}

	drawlist := imgui.GetWindowDrawList()
	cursor := imgui.GetCursorScreenPos()
	avail_size := imgui.GetContentRegionAvail()
	size := [2]f32 {
		size_arg.x == 0 ? avail_size.x : size_arg.x,
		size_arg.y == 0 ? avail_size.y : size_arg.y,
	}

	if size.x <= 1 || size.y <= 1 {return false}

	bar_width := size.x / f32(len(peaks))
	bar_height := size.y * 0.5
	middle := cursor.y + (size.y * 0.5)
	x_pos := cursor.x

	up_to_index := int(f32(len(peaks)) * (position^/length))

	for peak, index in peaks {
		peak_height := peak * bar_height
		pmin := [2]f32{x_pos, middle - peak_height}
		pmax := [2]f32{x_pos + bar_width, middle + peak_height}

		if (abs(pmin.y - pmax.y) < 1) {
			pmin.y -= 1
			pmax.y = pmin.y + 2
		}

		color := imgui.GetStyleColorVec4(.PlotLines)^
		if index > up_to_index {color.w *= 0.5}
		imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, imgui.GetColorU32ImVec4(color))
		x_pos += bar_width
	}

	if imgui.InvisibleButton(str_id, size) {
		click_pos := imgui.GetMousePos().x - cursor.x
		ratio := clamp(click_pos / size.x, 0, 1)
		position^ = ratio * length

		return true
	}

	return false
}

peak_meter :: proc(str_id: cstring, peaks: []f32, loud_color: [4]f32, quiet_color: [4]f32, req_size: [2]f32 = {0, 0}) -> bool {
	drawlist := imgui.GetWindowDrawList()
	avail_size := imgui.GetContentRegionAvail()
	cursor := imgui.GetCursorScreenPos()
	style := imgui.GetStyle()
	size := req_size

	channels := len(peaks)

	if channels == 0 {return false}

	if size.y == 0 {size.y = avail_size.y + style.FramePadding.y}
	if size.x == 0 {size.x = avail_size.x}

	bar_height := (size.y / f32(channels)) - 1
	y_offset: f32 = style.FramePadding.y
	
	for &peak in peaks {
		peak = clamp(peak, 0, 1)
		color := lerp(quiet_color, loud_color, peak)
		pmin := [2]f32{cursor.x, cursor.y + y_offset}
		pmax := [2]f32{pmin.x + size.x*peak, pmin.y + bar_height}
		imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, imgui.GetColorU32ImVec4(color))
		y_offset += bar_height + 1
	}

	return imgui.InvisibleButton(str_id, size)
}

input_text_with_suggestions :: proc(label: cstring, buf: []u8, suggestions: []cstring, selection_index: ^int) -> (active: bool, focused: bool) {
	buf_cstring := cstring(raw_data(buf))

	active |= imgui.InputText(label, buf_cstring, auto_cast len(buf))
	focused = imgui.IsItemFocused()
	input_box_size := imgui.GetItemRectSize()
	input_box_pos := imgui.GetItemRectMin()

	imgui.PushID(label)
	defer imgui.PopID()

	if len(suggestions) == 0 {return}

	if active {
		imgui.OpenPopup("##suggestions")
	}

	imgui.SetNextWindowPos({input_box_pos.x, input_box_pos.y + input_box_size.y})
	imgui.SetNextWindowSize({input_box_size.x, 0})
	if imgui.BeginPopup("##suggestions", {.NoSavedSettings, .NoFocusOnAppearing}) {
		defer imgui.EndPopup()

		if focused {
			if imgui.IsKeyPressed(.DownArrow) {
				selection_index^ += 1
			}
			else if imgui.IsKeyPressed(.UpArrow) {
				selection_index^ -= 1
			}
		}

		selection_index^ = clamp(selection_index^, 0, len(suggestions)-1)

		if focused && imgui.IsKeyPressed(.Enter) {
			copy(buf[:len(buf)-1], string(suggestions[selection_index^]))
			imgui.CloseCurrentPopup()
			active = true
		}
		else {
			for s, index in suggestions {
				if imgui.Selectable(s, index == selection_index^) {
					for &b in buf {b = 0}
					copy(buf[:len(buf)-1], string(s))
					imgui.CloseCurrentPopup()
					active = true
				}
			}
		}
	}

	return
}
