package sys

import imgui "src:thirdparty/odin-imgui"

Texture :: distinct uintptr

Video_Imgui_Repeat_Texture_Info :: struct {
	position: [4][2]f32,
	uv: [4][2]f32,
	color: u32,
	texture: imgui.TextureID,
}
