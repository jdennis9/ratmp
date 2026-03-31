#+private file
package main

import gl "vendor:OpenGL"
import "core:log"
import imgui_gl "src:thirdparty/odin-imgui/imgui_impl_opengl3"
import imgui "src:thirdparty/odin-imgui"

_Texture :: struct {
	id: u32,
}

@private
video_shutdown_opengl :: proc() {
	imgui_gl.Shutdown()
}

@private
video_init_opengl :: proc(set_gl_proc_address: gl.Set_Proc_Address_Type) -> bool {
	log.debug("Using OpenGL 3")

	if gl.impl_DrawElements == nil {
		gl.load_up_to(3, 0, set_gl_proc_address)
	}
	imgui_gl.Init() or_return

	_video_impl_imgui_new_frame = proc() {
		imgui_gl.NewFrame()
	}

	_video_impl_render_frame = proc() {
		gl.impl_ClearColor(0, 0, 0, 1)

		if gl.GetError() != gl.NO_ERROR {
			gl.Finish()
			handle_graphics_device_lost()
			global_flags |= {.VideoDeviceLost}
			return
		}

		gl.Clear(gl.COLOR_BUFFER_BIT)

		if draw_data := imgui.GetDrawData(); draw_data != nil {
			imgui_gl.RenderDrawData(draw_data)
		}
	}

	_video_impl_create_texture = proc(desc: Texture_Desc) -> (ptr: rawptr, ok: bool) {
		tex := new(_Texture)
		target :: gl.TEXTURE_2D
		defer if !ok do free(tex)

		gl.GenTextures(1, &tex.id)
		if tex.id == 0 do return

		gl.BindTexture(target, tex.id)
		defer gl.BindTexture(target, 0)
		gl.TexParameteri(target, gl.TEXTURE_WRAP_S, gl.REPEAT)
		gl.TexParameteri(target, gl.TEXTURE_WRAP_T, gl.REPEAT)
		gl.TexParameteri(target, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(target, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

		gl.TexImage2D(
			target, 0, gl.RGBA8, auto_cast desc.width, auto_cast desc.height,
			0, gl.RGBA, gl.UNSIGNED_BYTE, desc.data
		)

		ptr = tex
		ok = true
		return
	}

	_video_impl_destroy_texture = proc(ptr: rawptr) {
		tex := cast(^_Texture) ptr
		gl.DeleteTextures(1, &tex.id)
	}

	// Returns false if the texture has been destroyed or the device has been lost/reset
	_video_impl_get_texture_imgui_ref = proc(ptr: rawptr) -> (ref: imgui.TextureRef, ok: bool) {
		tex := cast(^_Texture) ptr
		ref._TexID = auto_cast tex.id
		ok = true

		return
	}

	_video_impl_resize_swapchain = proc(w, h: int) {}

	return true
}
