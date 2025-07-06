package client

import glm "core:math/linalg/glsl"

import imgui "src:thirdparty/odin-imgui"

lerp :: glm.lerp_f32

@private
_show_scrubber_widget :: proc(str_id: cstring, p_value: ^f32, min, max: f32, size_arg: imgui.Vec2 = {}, marker_interval: f32 = 10) -> bool {
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
		hovered ? imgui.GetColorU32(.NavHighlight) : imgui.GetColorU32(.HeaderActive),
		2
	)

	if imgui.IsItemDeactivated() {
		frac = clamp((mouse.x - cursor.x) / size.x, 0.0, 1.0)
		p_value^ = lerp(min, max, frac)
		return true
	}

	return false
}

@private
_waveform_seek_bar :: proc(
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

@private
_show_peak_meter_widget :: proc(str_id: cstring, peaks: []f32, req_size: [2]f32 = {0, 0}) -> bool {
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

	quiet_color := global_theme.custom_colors[.PeakQuiet]
	loud_color := global_theme.custom_colors[.PeakLoud]
	
	for &peak in peaks {
		peak = clamp(peak, 0, 1)
		color := glm.lerp(quiet_color, loud_color, peak)
		pmin := [2]f32{cursor.x, cursor.y + y_offset}
		pmax := [2]f32{pmin.x + size.x*peak, pmin.y + bar_height}
		imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, imgui.GetColorU32ImVec4(color))
		y_offset += bar_height + 1
	}

	return imgui.InvisibleButton(str_id, size)
}
