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

import "src:main/shared"
import "core:log"
import stbi "vendor:stb/image"
import imgui "src:thirdparty/odin-imgui"
import hm "core:container/handle_map"

// Textures are reference counted
Texture_Handle :: hm.Handle32

Texture_Desc :: struct {
	width, height: int,
	data: rawptr,
}

Texture :: struct {
	handle:        Texture_Handle,
	impl:          rawptr,
	ref_count:     int,
	device_serial: uint,
}

@(private="file")
_video: struct {
	textures: hm.Dynamic_Handle_Map(Texture, Texture_Handle),
}

_video_impl_imgui_new_frame:       proc()
_video_impl_render_frame:          proc()
_video_impl_create_texture:        proc(desc: Texture_Desc) -> (rawptr, bool)
_video_impl_destroy_texture:       proc(ptr: rawptr)
_video_impl_get_texture_imgui_ref: proc(ptr: rawptr) -> (imgui.TextureRef, bool)
_video_impl_resize_swapchain:      proc(width, height: int)

video_imgui_new_frame :: proc() {
	_video_impl_imgui_new_frame()
}

video_render_frame :: proc() {
	_video_impl_render_frame()
}

video_invalidate_textures :: proc() {
	it := hm.iterator_make(&_video.textures)
	for tex, _ in hm.iterate(&it) {
		_video_impl_destroy_texture(tex.impl)
	}
	hm.clear(&_video.textures)
}

video_resize_swapchain :: proc(w, h: int) {
	_video_impl_resize_swapchain(w, h)
}

handle_graphics_device_lost :: proc() -> bool {
	log.warn("Graphics device lost, freeing resources and reinitializing...")
	video_invalidate_textures()
	platform_destroy_window()
	platform_make_window() or_return
	return true
}

texture_create :: proc(desc: Texture_Desc) -> (handle: Texture_Handle, ok: bool) {
	ptr := _video_impl_create_texture(desc) or_return

	tex := Texture {
		impl = ptr,
		ref_count = 1,
	}

	handle = hm.add(&_video.textures, tex)
	ok = true
	return
}

texture_ref :: proc(h: Texture_Handle) -> bool {
	tex := hm.get(&_video.textures, h) or_return
	tex.ref_count += 1
	return true
}

texture_release :: proc(h: Texture_Handle) -> bool {
	tex := hm.get(&_video.textures, h) or_return
	tex.ref_count -= 1

	if tex.ref_count <= 0 {
		_video_impl_destroy_texture(tex.impl)
		hm.remove(&_video.textures, h)
	}

	return true
}

texture_get_imgui_ref :: proc(h: Texture_Handle) -> (ref: imgui.TextureRef, ok: bool) {
	tex := hm.get(&_video.textures, h) or_return
	return _video_impl_get_texture_imgui_ref(tex.impl)
}

texture_is_outdated :: proc(h: Texture_Handle) -> bool {
	_, found := hm.get(&_video.textures, h)
	if !found do return true
	return false
}

texture_create_from_file :: proc(
	path: string
) -> (handle: Texture_Handle, width, height: int, error: shared.Error) {
	path_buf: [512]u8
	path_cstr := cstring(&path_buf[0])
	copy(path_buf[:511], path)

	w, h: i32
	image_data := stbi.load(path_cstr, &w, &h, nil, 4)
	if image_data == nil do return {}, 0, 0, shared.Error_Code.NotFound
	defer stbi.image_free(image_data)

	width = auto_cast w
	height = auto_cast h

	desc := Texture_Desc {
		data = image_data,
		width = width,
		height = height,
	}

	handle = texture_create(desc) or_return
	return
}

texture_create_from_memory :: proc(data: []byte) -> (handle: Texture_Handle, width, height: int, ok: bool) {
	w, h: i32
	image_data := stbi.load_from_memory(raw_data(data), auto_cast len(data), &w, &h, nil, 4)
	if image_data == nil do return
	defer stbi.image_free(image_data)

	width = auto_cast w
	height = auto_cast h

	desc := Texture_Desc {
		data = image_data,
		width = width,
		height = height,
	}

	handle = texture_create(desc) or_return
	ok = true
	return
}

@init @(private="file")
_register_image_loaders :: proc "contextless" () {
	//image.register(.JPEG, jpeg.load_from_bytes, jpeg.destroy)
	//image.register(.PNG, png.load_from_bytes, png.destroy)
}
