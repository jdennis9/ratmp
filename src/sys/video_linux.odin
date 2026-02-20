/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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
package sys

import "vendor:glfw"
import gl "vendor:OpenGL"

import imgui "src:thirdparty/odin-imgui"
import imgui_gl "src:thirdparty/odin-imgui/imgui_impl_opengl3"

_gl_init :: proc(window: glfw.WindowHandle) {
	gl.load_up_to(3, 0, glfw.gl_set_proc_address)
}

_gl_clear_buffer :: proc() {
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

video_create_texture :: proc(data: rawptr, width, height: int) -> (imgui.TextureID, bool) {
	h: u32
	if gl.GenTextures == nil {return 0, false}
	gl.GenTextures(1, &h)
	if h == 0 {return 0, false}

	gl.BindTexture(gl.TEXTURE_2D, h)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, auto_cast width, auto_cast height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data)

	gl.BindTexture(gl.TEXTURE_2D, 0)

	return cast(imgui.TextureID) uintptr(h), true
}

video_create_dynamic_texture :: proc(width, height: int) -> (id: imgui.TextureID, ok: bool) {
	return video_create_texture(nil, width, height)
}

video_update_dynamic_texture :: proc(handle: imgui.TextureID, offset: [2]int, size: [2]int, data: rawptr) -> bool {
	h := u32(uintptr(handle))

	assert(data != nil)

	if size[0] <= 0 || size[1] <= 0 {return false}

	gl.BindTexture(gl.TEXTURE_2D, h)
	gl.TexSubImage2D(
		gl.TEXTURE_2D, 0, auto_cast offset.x, auto_cast offset.y,
		auto_cast size.x, auto_cast size.y, gl.RGBA, gl.UNSIGNED_BYTE, data
	)
	gl.BindTexture(gl.TEXTURE_2D, 0)

	return true
}

video_render_imgui_draw_data :: proc(dd: ^imgui.DrawData) {
	imgui_gl.RenderDrawData(dd)
}

video_destroy_texture :: proc(tex: imgui.TextureID) {
	h := cast(u32) uintptr(tex)
	if h != 0 {gl.DeleteTextures(1, &h)}
}

video_invalidate_imgui_objects :: proc () {
	imgui_gl.DestroyDeviceObjects()
}

video_create_imgui_objects :: proc() {
	imgui_gl.CreateDeviceObjects()
}

// For ImGui backends that use clamp address mode on samplers, this overrides them with repeat (used by spectogram)
video_imgui_callback_override_sampler :: proc "c" (drawlist: ^imgui.DrawList, cmd: ^imgui.DrawCmd) {
}

