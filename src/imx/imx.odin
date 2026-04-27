package imx

import "core:strconv"
import "core:reflect"
import "core:math/linalg"
import "core:fmt"
import imgui "src:thirdparty/odin-imgui"


text_unformatted :: proc(str: string) {
	base := raw_data(transmute([]u8) str)
	imgui.TextUnformatted(cstring(base), cstring(&base[len(str)]))
}

text_unformatted_ex :: proc(str: string, flags: imgui.TextFlags = {}) {
	base := raw_data(transmute([]u8) str)
	imgui.TextEx(cstring(base), cstring(&base[len(str)]), flags)
}

text :: proc($BUF_SIZE: uint, args: ..any, sep := " ") {
	buf: [BUF_SIZE]u8
	text_unformatted(fmt.bprint(buf[:], ..args, sep=sep))
}

textf :: proc($BUF_SIZE: uint, format: string, args: ..any) {
	buf: [BUF_SIZE]u8
	text_unformatted(fmt.bprintf(buf[:], format, ..args))
}

title_text :: proc(args: ..any, sep := " ") {
	buf: [256]u8
	fmt.bprint(buf[:], ..args, sep=sep)
	push_font_scale(1.25)
	imgui.SeparatorText(cstring(&buf[0]))
	imgui.PopFont()
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

begin :: proc(title: cstring, p_open: ^bool = nil, flags: imgui.WindowFlags = {}) -> bool {
	if imgui.Begin(title, p_open, flags) do return true
	else do imgui.End()
	return false
}

color_edit_u32 :: proc(label: cstring, color: ^u32, flags: imgui.ColorEditFlags = {}) -> bool {
	v := imgui.ColorConvertU32ToFloat4(color^)
	if imgui.ColorEdit4(label, &v, flags) {
		color^ = imgui.GetColorU32ImVec4(v)
		return true
	}

	return false
}

select_enum :: proc(label: cstring, v: ^$E) -> (changed: bool) {
	label_buf: [128]u8
	str := cstring(&label_buf[0])

	copy(label_buf[:127], reflect.enum_name_from_value(v^) or_else "")

	imgui.BeginCombo(label, str) or_return
	defer imgui.EndCombo()

	for e in E {
		buf: [128]u8
		if e != v^ {
			copy(buf[:127], reflect.enum_name_from_value(e) or_continue)
			if imgui.MenuItem(cstring(&buf[0])) {
				changed = true
				v^ = e
			}
		}
	}

	return
}

push_font_scale :: proc(scale: f32) {
	imgui.PushFontFloat(nil, imgui.GetStyle().FontSizeBase * scale)
}

is_item_double_clicked :: proc(button := imgui.MouseButton.Left) -> bool {
	return imgui.IsItemClicked(button) && imgui.IsMouseDoubleClicked(button)
}

begin_kv_table :: proc(str_id: cstring, flags: imgui.TableFlags) -> bool {
	return imgui.BeginTable(str_id, 2, flags)
}

kv_row :: proc(name: string, args: ..any, sep := "") -> (active: bool) {
	buf: [1024]u8
	fmt.bprint(buf[:1023], ..args, sep=sep)
	imgui.TableNextRow()
	if imgui.TableSetColumnIndex(0) do text_unformatted(name)
	if imgui.TableSetColumnIndex(1) {
		active |= imgui.Selectable(cstring(&buf[0]))
	}
	return
}

kv_rowf :: proc(name: string, format: string, args: ..any) -> (active: bool) {
	buf: [1024]u8
	fmt.bprintf(buf[:1023], format, ..args)
	imgui.TableNextRow()
	if imgui.TableSetColumnIndex(0) do text_unformatted(name)
	if imgui.TableSetColumnIndex(1) {
		active |= imgui.Selectable(cstring(&buf[0]), )
	}
	return
}

end_kv_table :: proc() {
	imgui.EndTable()
}

number_picker :: proc(label: cstring, options: []int, current: ^int) -> (changed: bool) {
	preview: [16]u8
	strconv.write_int(preview[:15], auto_cast current^, 10)

	imgui.BeginCombo(label, cstring(&preview[0])) or_return
	defer imgui.EndCombo()

	changed |= number_picker_menu_items(options, current)

	return
}

number_picker_menu_items :: proc(options: []int, current: ^int) -> (changed: bool) {
	for opt in options {
		buf: [16]u8
		strconv.write_int(buf[:15], auto_cast opt, 10)

		if imgui.MenuItem(cstring(&buf[0]), nil, opt == current^) {
			current^ = opt
			changed = true
		}
	}

	return
}

string_to_ptrs :: proc(str: string) -> (cstring, cstring) {
	base := raw_data(str)
	return cstring(base), cstring(&base[len(str)])
}
