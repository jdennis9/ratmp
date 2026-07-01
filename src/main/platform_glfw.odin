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
package main

import "base:runtime"
import "core:log"
import "vendor:glfw"
import imgui_glfw "src:thirdparty/odin-imgui/imgui_impl_glfw"

@(private="file")
_glfw: struct {
	window:     glfw.WindowHandle,
	video_impl: Video_Impl,
	events:     Platform_Events,
}

platform_init_glfw :: proc() -> bool {
	log.debug("Using GLFW platform")

	// libdecor will sometimes cause a crash when calling glfw.CreateWindow()
	when ODIN_OS == .Linux {
		glfw.WindowHint(glfw.WAYLAND_DISABLE_LIBDECOR, true)
		glfw.WindowHint(glfw.WAYLAND_LIBDECOR, false)
		glfw.WindowHint(glfw.WAYLAND_PREFER_LIBDECOR, false)
	}
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 0)

	glfw.Init() or_return

	close_proc :: proc "c" (win: glfw.WindowHandle) {
		_glfw.events.window_closed = true
	}

	size_proc :: proc "c" (win: glfw.WindowHandle, w, h: i32) {
		context = runtime.default_context()
		video_resize_swapchain(auto_cast w, auto_cast h)
	}
	
	_platform_impl_make_window = proc() -> bool {
		_glfw.window = glfw.CreateWindow(1600, 900, "RAT MP", nil, nil)
		_glfw.video_impl = .OpenGL
		
		glfw.MakeContextCurrent(_glfw.window)
		
		glfw.SetWindowCloseCallback(_glfw.window, close_proc)
		glfw.SetWindowSizeCallback(_glfw.window, size_proc)
		
		imgui_glfw.InitForOpenGL(_glfw.window, true) or_return
		
		video_init_opengl(glfw.gl_set_proc_address) or_return
		glfw.SwapInterval(1)
		
		glfw.PostEmptyEvent()

		return true
	}

	_platform_impl_destroy_window = proc() {
		log.debug("Cleaning up GLFW...")
		imgui_glfw.Shutdown()
		video_invalidate_textures()
		video_shutdown_opengl()
		glfw.DestroyWindow(_glfw.window)
		_glfw.window = nil
	}

	_platform_impl_shutdown = proc() {
		glfw.Terminate()
	}

	_platform_impl_imgui_new_frame = proc() {
		imgui_glfw.NewFrame()
	}

	_platform_impl_poll_events = proc() -> Platform_Events {
		_glfw.events = {}
		glfw.PollEvents()
		return _glfw.events
	}

	_platform_impl_wait_events = proc() -> Platform_Events {
		_glfw.events = {}
		glfw.WaitEventsTimeout(0.1)
		return _glfw.events
	}
	
	_platform_impl_set_window_size = proc(w, h: int) {
		if _glfw.window != nil {
			glfw.SetWindowSize(_glfw.window, auto_cast w, auto_cast h)
		}
	}

	_platform_impl_flush_events = proc() {
		glfw.PostEmptyEvent()
	}

	_platform_impl_swap_buffers = proc() {
		if _glfw.video_impl == .OpenGL do glfw.SwapBuffers(_glfw.window)
	}

	_platform_impl_is_window_visible = proc() -> bool {
		return _glfw.window != nil && glfw.GetWindowAttrib(_glfw.window, glfw.VISIBLE) != 0
	}

	_platform_impl_set_window_visible = proc(visible: bool) {
		if visible && _glfw.window == nil {
			_platform_impl_make_window()
		}
		else if !visible && _glfw.window != nil {
			_platform_impl_destroy_window()
		}
	}

	_platform_impl_set_window_title = proc(title: cstring) {
		if _glfw.window == nil do return
		glfw.SetWindowTitle(_glfw.window, title)
	}

	return true
}
