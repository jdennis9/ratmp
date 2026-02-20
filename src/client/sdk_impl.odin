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

import "src:client/imx"
import "src:../sdk"

import imgui "src:thirdparty/odin-imgui"

get_sdk_impl :: proc() -> (ui: sdk.UI_Procs, draw: sdk.Draw_Procs) {
	ui.begin = proc(str_id: cstring, p_open: ^bool) -> bool {
		if imgui.Begin(str_id, p_open) {
			return true
		}
		else {
			imgui.End()
			return false
		}
	}

	ui.end = proc() {imgui.End()}

	ui.dummy = proc(size: [2]f32) {imgui.Dummy(size)}

	ui.invisible_button = proc(str_id: cstring, size: [2]f32) -> bool {
		return imgui.InvisibleButton(str_id, size)
	}

	ui.text = proc(args: ..any) {
		imx.text(4096, ..args)
	}

	ui.textf = proc(format: string, args: ..any) {
		imx.textf(4096, format, ..args)
	}

	ui.selectable = proc(label: cstring, selected: bool) -> bool {
		return imgui.Selectable(label, selected)
	}

	ui.toggleable = proc(label: cstring, selected: ^bool) -> bool {
		return imgui.SelectableBoolPtr(label, selected)
	}

	ui.button = proc(label: cstring) -> bool {
		return imgui.Button(label)
	}

	ui.begin_combo = proc(label: cstring, preview: cstring) -> bool {
		return imgui.BeginCombo(label, preview)
	}

	ui.end_combo = proc() {
		imgui.EndCombo()
	}

	ui.get_cursor = proc() -> [2]f32 {
		return imgui.GetCursorScreenPos()
	}

	ui.text_unformatted = proc(str: string) {
		imx.text_unformatted(str)
	}

	ui.checkbox = proc(label: cstring, value: ^bool) -> bool {
		return imgui.Checkbox(label, value)
	}

	ui.get_window_drawlist = proc() -> sdk.Draw_List {
		return auto_cast imgui.GetWindowDrawList()
	}

	ui.float_slider = proc(label: cstring, value: ^f32, vmin, vmax: f32) -> bool {
		return imgui.SliderFloat(label, value, vmin, vmax)
	}

	draw.rect = proc(drawlist: sdk.Draw_List, pmin, pmax: [2]f32, color: u32, thickness: f32, rounding: f32) {
		imgui.DrawList_AddRect(auto_cast drawlist, pmin, pmax, color, rounding, {}, thickness)
	}

	draw.many_rects_filled = proc(drawlist: sdk.Draw_List, rects: []sdk.Rect, colors: []u32, rounding: f32) {
		for r, index in rects {
			color := colors[index]
			imgui.DrawList_AddRectFilled(auto_cast drawlist, r.min, r.max, color, rounding)
		}
	}

	draw.rect_filled = proc(drawlist: sdk.Draw_List, pmin, pmax: [2]f32, color: u32, rounding: f32) {
		drawlist := imgui.GetWindowDrawList()
		if drawlist == nil do return
		imgui.DrawList_AddRectFilled(auto_cast drawlist, pmin, pmax, color, rounding)
	}

	return
}
