package imx

import "core:math/linalg"
import "core:log"
import "core:mem"
import "base:runtime"
import "core:slice"
import "core:fmt"
import "core:reflect"
import imgui "src:thirdparty/odin-imgui"

text_unformatted :: proc(str: string) {
	base := raw_data(transmute([]u8) str)
	imgui.TextUnformatted(cstring(base), cstring(&base[len(str)]))
}

text :: proc($BUF_SIZE: uint, args: ..any) {
	buf: [BUF_SIZE]u8
	text_unformatted(fmt.bprint(buf[:], ..args))
}

textf :: proc($BUF_SIZE: uint, format: string, args: ..any) {
	buf: [BUF_SIZE]u8
	text_unformatted(fmt.bprintf(buf[:], format, ..args))
}


typeid_to_data_type :: proc(t: typeid) -> (s: imgui.DataType, ok: bool) {
	ok = true
	switch t {
		case f32: s = .Float
		case f64: s = .Double
		case i8: s = .S8
		case i16: s = .S16
		case i32: s = .S32
		case int, i64: s = .S64
		case u8: s = .U8
		case u16: s = .U16
		case u32: s = .U32
		case uint, u64: s = .U64
		case: ok = false
	}
	return
}

begin_combo :: proc($BUF_SIZE: uint, label: cstring, preview: string) -> bool {
	buf: [BUF_SIZE]u8
	copy(buf[:BUF_SIZE-1], preview)
	return imgui.BeginCombo(label, cstring(&buf[0]))
}

menu_item :: proc($BUF_SIZE: uint, label: string) -> bool {
	buf: [BUF_SIZE]u8
	copy(buf[:BUF_SIZE-1], label)
	return imgui.MenuItem(cstring(&buf[0]))
}

scrubber :: proc(
	str_id: cstring, p_value: ^int, min, max: int,
	size_arg: imgui.Vec2 = {}, marker_interval: int = 10
) -> bool {
	size: [2]f32
	style := imgui.GetStyle()
	drawlist := imgui.GetWindowDrawList()
	span := max - min
	frac := (f32(p_value^) + f32(min)) / f32(span)
	avail_size := imgui.GetContentRegionAvail()
	cursor := imgui.GetCursorScreenPos() + style.FramePadding*1.5
	mouse := imgui.GetMousePos()

	size.x = size_arg.x == 0 ? avail_size.x : size_arg.x
	size.y = size_arg.y == 0 ? avail_size.y : size_arg.y

	size -= style.FramePadding*2
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

	imgui.DrawList_AddCircleFilled(
		drawlist, {cursor.x + frac * size.x, cursor.y + size.y / 2}, scrubber_size.y,
		hovered ? imgui.GetColorU32(.NavCursor) : imgui.GetColorU32(.HeaderActive)
	)

	if imgui.IsItemDeactivated() {
		frac = clamp((mouse.x - cursor.x) / size.x, 0.0, 1.0)
		p_value^ = int(linalg.lerp(f32(min), f32(max), frac))
		return true
	}
	
	// Markers
	/*{
		marker_count := (max - min) / marker_interval
		if marker_count != 0 {
			marker_gap := size.x / f32(marker_count)
			pos := cursor

			for m in 0..<marker_count {
				imgui.DrawList_AddLine(drawlist, pos, {pos.x, pos.y + avail_size.y}, imgui.GetColorU32(.PlotLines))
				pos.x += marker_gap
			}
		}
	}*/

	return false
}

set_item_tooltip :: proc(str: string) {
	if imgui.BeginItemTooltip() {
		text_unformatted(str)
		imgui.EndTooltip()
	}
}
