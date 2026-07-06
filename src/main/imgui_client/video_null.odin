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
package client

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
