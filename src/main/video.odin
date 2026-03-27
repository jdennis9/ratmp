package main

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
	handle: Texture_Handle,
	impl: rawptr,
	ref_count: int,
	device_serial: uint,
}

@(private="file")
_video: struct {
	textures: hm.Dynamic_Handle_Map(Texture, Texture_Handle),
}

_video_impl_imgui_new_frame: proc()
_video_impl_render_frame: proc()
_video_impl_create_texture: proc(desc: Texture_Desc) -> (rawptr, bool)
_video_impl_destroy_texture: proc(ptr: rawptr)
// Returns false if the texture has been destroyed or the device has been lost/reset
_video_impl_get_texture_imgui_ref: proc(ptr: rawptr) -> (imgui.TextureRef, bool)
_video_impl_resize_window: proc(width, height: int)

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

texture_create_from_file :: proc(path: string) -> (handle: Texture_Handle, width, height: int, ok: bool) {
	path_buf: [512]u8
	path_cstr := cstring(&path_buf[0])
	copy(path_buf[:511], path)

	w, h: i32
	image_data := stbi.load(path_cstr, &w, &h, nil, 4)
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
