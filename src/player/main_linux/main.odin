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
package main_linux;

import "base:runtime";
import "core:log";

import "vendor:glfw";

import imgui "../../libs/odin-imgui";
import imgui_glfw "../../libs/odin-imgui/imgui_impl_glfw";

import "../build";
import "../signal";
import com "../main_common";
import "../video/opengl";

@private
this: struct {
	window: glfw.WindowHandle,
	ctx: runtime.Context,
	want_exit: bool,
	signals: [dynamic]signal.Signal,
};

@private
_signal_handler :: proc(sig: signal.Signal) {
	if sig == .Exit {
		this.want_exit = true;
	}
}

@private
_signal_post_callback :: proc(sig: signal.Signal) {
	append(&this.signals, sig);
}

main_linux :: proc() -> bool {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger();
	}
	else {
		// @TODO
	}

	this.ctx = context;

	imgui.CreateContext();
	defer imgui.DestroyContext();

	signal.init(_signal_post_callback);
	signal.install_handler(_signal_handler);

	glfw.Init();
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3);
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 0);
	glfw.WindowHint_bool(glfw.TRANSPARENT_FRAMEBUFFER, true);
	this.window = glfw.CreateWindow(800, 800, build.PROGRAM_NAME_AND_VERSION, nil, nil);
	imgui_glfw.InitForOpenGL(this.window, true);

	opengl.init_for_linux(this.window) or_return;
	defer opengl.shutdown();
	
	com.init();
	defer com.shutdown();

	glfw.ShowWindow(this.window);
	for !this.want_exit {
		// Flush signals
		for sig in this.signals {
			signal.broadcast_immediate(sig);
		}
		clear(&this.signals);

		glfw.PollEvents();

		if opengl.begin_frame() {
			com.frame();
			opengl.end_frame();
		}
	}

	return true;
}

main :: proc() {
	main_linux();
}
