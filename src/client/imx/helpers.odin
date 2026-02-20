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

import "src:global"
import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

text_unformatted :: proc(str: string) {
	n := len(str)
	if n == 0 {return}
	p := transmute([]u8) str
	end := &((raw_data(p))[len(p)])
	imgui.TextUnformatted(cstring(raw_data(p)), cstring(end))
}

text :: proc($MAX_CHARS: uint, args: ..any, sep := " ") {
	buf: [MAX_CHARS]u8 = ---
	formatted := fmt.bprint(buf[:], ..args, sep=sep)
	text_unformatted(formatted)
}

textf :: proc($MAX_CHARS: uint, format: string, args: ..any) {
	buf: [MAX_CHARS]u8 = ---
	formatted := fmt.bprintf(buf[:], format, ..args)
	text_unformatted(formatted)
}

separator_text :: proc(str: string) {
	buf: [256]u8
	copy(buf[:255], str)
	imgui.SeparatorText(cstring(&buf[0]))
}

hyperlink :: proc(str: string) {
	buf: [512]u8
	copy(buf[:511], str)
	imgui.TextLink(cstring(&buf[0]))
}

set_tooltip :: proc(str: string) {
	buf: [128]u8
	copy(buf[:127], str)
	imgui.SetTooltip(cstring(&buf[0]))
}

set_item_tooltip_unformatted :: proc(str: string) {
	buf: [512]u8
	copy(buf[:511], str)
	imgui.SetItemTooltip(cstring(&buf[0]))
}

set_item_tooltip :: proc($BUF_SIZE: uint, args: ..any) {
	buf: [BUF_SIZE]u8
	set_item_tooltip_unformatted(fmt.bprint(buf[:], ..args))
}

begin_status_bar :: proc() -> bool {
	window_flags := imgui.WindowFlags{
		.NoScrollbar, 
		.NoSavedSettings, 
		.MenuBar,
	}

	imgui.BeginViewportSideBar(
		"##status_bar",
		imgui.GetMainViewport(),
		.Down,
		imgui.GetFrameHeight(),
		window_flags,
	) or_return

	return imgui.BeginMenuBar()
}

end_status_bar :: proc() {
	imgui.EndMenuBar()
	imgui.End()
}

SCROLLING_TEXT_CHARS_INTERVAL :: 0.5

// Pixels per second
SCROLLING_TEXT_SPEED :: 60
// Pixels of spacing between incoming and outgoing scrolling text
SCROLLING_TEXT_SPACING :: 16

Scrolling_Text_Mode :: enum {StartIndex, DrawOffset}

draw_scrolling_text :: proc(pos: [2]f32, text: string, max_width: f32, text_width_arg: Maybe(f32) = nil) {
	timer := global.uptime
	ptr := raw_data(text)
	text_width := text_width_arg.? or_else calc_text_size(text).x
	bullet_pos: [2]f32
	offset: f32

	drawlist := imgui.GetWindowDrawList()
	cursor := pos

	if text_width < max_width {
		imgui.DrawList_AddText(drawlist, cursor, imgui.GetColorU32(.Text), cstring(&ptr[0]), cstring(&ptr[len(text)]))
		return
	}

	wrap :: proc(v: f32, w: f32) -> f32 {
		return v - (f32(int(v / w)) * w)
	}

	offset = wrap(f32(timer * SCROLLING_TEXT_SPEED), text_width + SCROLLING_TEXT_SPACING)
	bullet_pos.x = cursor.x - offset + (SCROLLING_TEXT_SPACING/2) + text_width
	bullet_pos.y = cursor.y + (imgui.GetTextLineHeight() / 2)

	imgui.DrawList_AddText(
		drawlist, cursor - {offset, 0}, imgui.GetColorU32(.Text),
		cstring(&ptr[0]), cstring(&ptr[len(text)])
	)
	imgui.DrawList_AddText(
		drawlist, cursor - {offset, 0} + {text_width + SCROLLING_TEXT_SPACING, 0},
		imgui.GetColorU32(.Text),
		cstring(&ptr[0]), cstring(&ptr[len(text)])
	)
	imgui.DrawList_AddRectFilled(
		drawlist, bullet_pos - {2, 2}, bullet_pos + {2, 2},
		imgui.GetColorU32(.TextDisabled)
	)
}

scrolling_text :: proc(text: string, max_width: f32, text_width_arg: Maybe(f32) = nil, mode := Scrolling_Text_Mode.DrawOffset) {
	ptr := raw_data(text)
	text_width := text_width_arg.? or_else calc_text_size(text).x
	timer := global.uptime

	switch mode {
		case .StartIndex:
			avg_char_width := text_width / f32(len(text))
			chars_fit_in_width := int(max_width / avg_char_width)

			if text_width < max_width || chars_fit_in_width >= len(text) {
				text_unformatted(text)
				return
			}

			offset := int(timer / SCROLLING_TEXT_CHARS_INTERVAL) % (len(text) - chars_fit_in_width)
			imgui.TextUnformatted(cstring(&ptr[offset]), cstring(&ptr[len(text)]))

		case .DrawOffset:
			draw_scrolling_text(imgui.GetCursorScreenPos(), text, max_width, text_width_arg)
			//imgui.NewLine()
			imgui.Dummy({max_width + imgui.GetStyle().ItemSpacing.x, 0})
	}
}

scrolling_selectable :: proc(buf: []u8, text: string, timer: f64, max_width: f32, text_width_arg: Maybe(f32) = nil, selected := false, flags := imgui.SelectableFlags{}) -> bool {
	ptr := raw_data(text)
	text_width := text_width_arg.? or_else calc_text_size(text).x

	avg_char_width := text_width / f32(len(text))
	chars_fit_in_width := int(max_width / avg_char_width)

	if text_width < max_width || chars_fit_in_width >= len(text) {
		copy(buf[:len(buf)-1], text)
		return imgui.Selectable(cstring(raw_data(buf)), selected, flags)
	}
	
	offset := int(timer / SCROLLING_TEXT_CHARS_INTERVAL) % (len(text) - chars_fit_in_width)
	str := fmt.bprint(buf[:len(buf)-1], cstring(&ptr[offset]), "###", text, sep = "")
	buf[len(str)] = 0
	return imgui.Selectable(cstring(raw_data(buf)), selected, flags)
}

calc_text_size :: proc(text: string) -> [2]f32 {
	ptr := raw_data(text)
	return imgui.CalcTextSize(cstring(ptr), cstring(&ptr[len(text)]))
}

is_key_chord_pressed :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsKeyChordPressed(auto_cast(mods | key))
}

get_window_bounding_box :: proc() -> (r: imgui.Rect) {
	r.Min = imgui.GetWindowPos()
	r.Max = r.Min + imgui.GetWindowSize()
	return r
}
