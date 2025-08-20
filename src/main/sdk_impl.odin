#+private file
package main

import imgui "src:thirdparty/odin-imgui"

import "src:client"
import "src:client/imx"
import "src:server"
import "src:analysis"
import "src:../sdk"

Spectrum_Analyser_Settings :: struct {
	band_count: int,
}

ctx: struct {
	cl: ^client.Client,
	sv: ^server.Server,
	drawlist: ^imgui.DrawList,
	spectrum_analysers: map[Spectrum_Analyser_Settings]analysis.Spectrum_Analyzer,
}

@private
sdk_proc_addr: sdk.SDK

_sdk_version :: proc() -> sdk.Version {
	return {0, 1, 0}
}
_get_playing_track_id :: proc() -> sdk.Track_ID {
	return auto_cast ctx.sv.current_track_id
}

_ui_get_cursor :: proc() -> [2]f32 {
	return imgui.GetCursorScreenPos()
}
_ui_begin :: proc(str_id: cstring, p_open: ^bool) -> bool {
	if imgui.Begin(str_id, p_open) {
		ctx.drawlist = imgui.GetWindowDrawList()
		return true
	}
	else {
		imgui.End()
		return false
	}
}
_ui_end :: proc() {
	imgui.End()
}
_ui_dummy :: proc(size: [2]f32) {
	imgui.Dummy(size)
}
_ui_invisible_button :: proc(str_id: cstring, size: [2]f32) -> bool {
	return imgui.InvisibleButton(str_id, size)
}
_ui_text :: proc(args: ..any) {
	imx.text(4096, ..args)
}
_ui_textf :: proc(format: string, args: ..any) {
	imx.textf(4096, format, ..args)
}
_ui_selectable :: proc(label: cstring, selected: bool) -> bool {
	return imgui.Selectable(label, selected)
}
_ui_toggleable :: proc(label: cstring, selected: ^bool) -> bool {
	return imgui.SelectableBoolPtr(label, selected)
}
_ui_button :: proc(label: cstring) -> bool {
	return imgui.Button(label)
}

_draw_many_rects :: proc(rects: []sdk.Rect, colors: []u32, thickness: f32, rounding: f32) {
	for r, index in rects {
		color := colors[index]
		imgui.DrawList_AddRect(ctx.drawlist, r.pmin, r.pmax, color, rounding, {}, thickness)
	}
}
_draw_rect :: proc(pmin, pmax: [2]f32, color: u32, thickness: f32, rounding: f32) {
	imgui.DrawList_AddRect(ctx.drawlist, pmin, pmax, color, rounding, {}, thickness)
}
_draw_many_rects_filled :: proc(rects: []sdk.Rect, colors: []u32, rounding: f32) {
	for r, index in rects {
		color := colors[index]
		imgui.DrawList_AddRectFilled(ctx.drawlist, r.pmin, r.pmax, color, rounding)
	}
}
_draw_rect_filled :: proc(pmin, pmax: [2]f32, color: u32, rounding: f32) {
	imgui.DrawList_AddRectFilled(ctx.drawlist, pmin, pmax, color, rounding)
}

@private
sdk_init :: proc(cl: ^client.Client, sv: ^server.Server) {
	ctx.cl = cl
	ctx.sv = sv

	s := &sdk_proc_addr
	s.version = _sdk_version
	s.get_playing_track_id = _get_playing_track_id

	s.draw_rect = _draw_rect
	s.draw_many_rects = _draw_many_rects
	s.draw_rect_filled = _draw_rect_filled
	s.draw_many_rects_filled = _draw_many_rects_filled

	s.ui_get_cursor = _ui_get_cursor
	s.ui_begin = _ui_begin
	s.ui_end = _ui_end
	s.ui_dummy = _ui_dummy
	s.ui_invisible_button = _ui_invisible_button
	s.ui_text = _ui_text
	s.ui_textf = _ui_textf
	s.ui_text_unformatted = imx.text_unformatted
	s.ui_selectable = _ui_selectable
	s.ui_toggleable = _ui_toggleable
	s.ui_button = _ui_button
}
