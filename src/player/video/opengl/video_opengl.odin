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
package video_opengl;

import "vendor:glfw";
import gl "vendor:OpenGL";

import imgui "../../../libs/odin-imgui";
import imgui_gl "../../../libs/odin-imgui/imgui_impl_opengl3";
import imgui_glfw "../../../libs/odin-imgui/imgui_impl_glfw";

import com "..";

@private
this: struct {
	window: glfw.WindowHandle,
};

init_for_linux :: proc(window: glfw.WindowHandle) -> bool {
	glfw.MakeContextCurrent(window);
	gl.load_up_to(3, 0, glfw.gl_set_proc_address);
	this.window = window;
	com.impl.create_texture = create_texture;
	com.impl.destroy_texture = destroy_texture;
	com.impl.invalidate_imgui_objects = invalidate_imgui_objects;
	com.impl.create_imgui_objects = create_imgui_objects;
	return imgui_gl.Init();
}

shutdown :: proc() {
	imgui_gl.Shutdown();
	imgui_glfw.Shutdown();
}

begin_frame :: proc() -> bool {
	imgui_glfw.NewFrame();
	imgui_gl.NewFrame();
	imgui.NewFrame();

	gl.ClearColor(0, 0, 0, 0.5);
	gl.Clear(gl.COLOR_BUFFER_BIT);

	return true;
}

end_frame :: proc() {
	imgui.Render();
	draw_data := imgui.GetDrawData();
	if draw_data != nil {
		imgui_gl.RenderDrawData(draw_data);
	}

	glfw.SwapBuffers(this.window);
}

invalidate_imgui_objects :: proc() {
	imgui_gl.DestroyDeviceObjects();
}

create_imgui_objects :: proc() {
	imgui_gl.CreateDeviceObjects();
}

create_texture :: proc(width, height: int, data: rawptr) -> (out: com.Texture, ok: bool) {
	handle: u32;

	gl.GenTextures(1, &handle);
	if handle == 0 {return}
	gl.BindTexture(gl.TEXTURE_2D, handle);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
	gl.BindTexture(gl.TEXTURE_2D, 0);

	out.id = cast(imgui.TextureID) cast(uintptr) handle;
	ok = true;
	return;
}

destroy_texture :: proc(tex: com.Texture) {
	handle := cast(u32) cast(uintptr) tex.id;
	gl.DeleteTextures(1, &handle);
}
