/*
	RAT MP: A lightweight graphical music player
    Copyright (C) 2025 Jamie Dennis

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
package video

import stbi "vendor:stb/image"
import "core:os"

import imgui "libs:odin-imgui"

//Texture :: imgui.TextureID;

Texture :: struct {
	impl: rawptr,
	id: imgui.TextureID,
}

Impl :: struct {
	create_texture: proc(width, height: int, data: rawptr) -> (Texture, bool),
	destroy_texture: proc(texture: Texture),
	invalidate_imgui_objects: proc(),
	create_imgui_objects: proc(),
}

// Set by backend on initialization
impl: Impl

load_texture :: proc(filename: string) -> (texture: Texture, w: int, h: int, ok: bool) {
	file := os.read_entire_file_from_filename(filename) or_return
	defer delete(file)

	width, height: i32

	image := stbi.load_from_memory(
		raw_data(file), auto_cast len(file),
		&width, &height, nil, 4
	)

	if image == nil {return}
	defer stbi.image_free(image)

	w = int(width)
	h = int(height)
	texture = impl.create_texture(w, h, image) or_return
	ok = true
	return
}
