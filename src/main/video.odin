package main

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
}

@(private="file")
_video: struct {
	textures: hm.Dynamic_Handle_Map(Texture, Texture_Handle)
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


