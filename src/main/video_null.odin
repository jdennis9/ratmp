package main

import imgui "src:thirdparty/odin-imgui"

video_init_null :: proc() {
	_video_impl_imgui_new_frame = proc() {
	}

	_video_impl_render_frame = proc() {
		draw_data := imgui.GetDrawData()
		if draw_data == nil do return
		if draw_data.Textures == nil do return

		for tex in (cast([^]^imgui.TextureData)draw_data.Textures.Data)[:draw_data.Textures.Size] {
			if tex.Status == .WantCreate || tex.Status == .WantDestroy {
				imgui.TextureData_SetStatus(tex, .OK)
			}
			if tex.Status == .WantDestroy {
				imgui.TextureData_SetTexID(tex, 0)
				imgui.TextureData_SetStatus(tex, .Destroyed)
			}
		}
	}

	_video_impl_create_texture = proc(desc: Texture_Desc) -> (ptr: rawptr, ok: bool) {
		return
	}

	_video_impl_destroy_texture = proc(ptr: rawptr) {
	}

	// Returns false if the texture has been destroyed or the device has been lost/reset
	_video_impl_get_texture_imgui_ref = proc(ptr: rawptr) -> (ref: imgui.TextureRef, ok: bool) {
		return {}, true
	}
}
