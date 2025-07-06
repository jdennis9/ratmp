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

imgui_create_texture :: proc(data: rawptr, width, height: int) -> (imgui.TextureID, bool) {
	h: u32
	if gl.GenTextures == nil {return nil, false}
	gl.GenTextures(1, &h)
	if h == 0 {return nil, false}

	gl.BindTexture(gl.TEXTURE_2D, h)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, auto_cast width, auto_cast height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data)

	gl.BindTexture(gl.TEXTURE_2D, 0)

	return cast(imgui.TextureID) uintptr(h), true
}

imgui_render_draw_data :: proc(dd: ^imgui.DrawData) {
	imgui_gl.RenderDrawData(dd)
}

imgui_destroy_texture :: proc(tex: imgui.TextureID) {
	h := cast(u32) uintptr(tex)
	if h != 0 {gl.DeleteTextures(1, &h)}
}

imgui_invalidate_objects :: proc () {
	imgui_gl.DestroyDeviceObjects()
}

imgui_create_objects :: proc() {
	imgui_gl.CreateDeviceObjects()
}
