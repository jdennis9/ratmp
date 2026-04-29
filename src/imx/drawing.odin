package imx

import "core:math/linalg"
import imgui "src:thirdparty/odin-imgui"

draw_bars :: proc(
	drawlist: ^imgui.DrawList,
	bb_min, bb_max: [2]f32,
	values: []f32,
	low_color_u, high_color_u: u32,
	spacing: f32 = 1,
) {
	x_offset: f32 = 0
	width := bb_max.x - bb_min.x
	height := bb_max.y - bb_min.y
	gap: f32 = width / f32(len(values))
	bar_width := gap - spacing
	low_color  := imgui.ColorConvertU32ToFloat4(low_color_u)
	high_color := imgui.ColorConvertU32ToFloat4(high_color_u)

	for v in values {
		top_color := imgui.GetColorU32ImVec4(linalg.lerp(low_color, high_color, v))

		imgui.DrawList_AddRectFilledMultiColor(
			drawlist,
			bb_min + {x_offset, 0},
			bb_min + {x_offset + bar_width, v * height},
			low_color_u, low_color_u,
			top_color, top_color,
		)

		x_offset += gap
	}
}
