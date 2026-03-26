package main

import "core:log"
import "vendor:glfw"
import imgui_glfw "src:thirdparty/odin-imgui/imgui_impl_glfw"

@(private="file")
_glfw: struct {
	window: glfw.WindowHandle,
	video_impl: Video_Impl,
	events: Platform_Events,
}

platform_init_glfw :: proc() {
	log.debug("Using GLFW platform")

	_platform_impl_set_gl_proc_address = glfw.gl_set_proc_address

	close_proc :: proc "c" (win: glfw.WindowHandle) {
		_glfw.events.window_closed = true
	}

	_platform_impl_make_window = proc() -> bool {
		glfw.Init() or_return

		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 0)
		
		_glfw.window = glfw.CreateWindow(1600, 900, "RAT MP", nil, nil)
		
		glfw.MakeContextCurrent(_glfw.window)
		glfw.SwapInterval(1)

		glfw.SetWindowCloseCallback(_glfw.window, close_proc)

		imgui_glfw.InitForOpenGL(_glfw.window, true)
		
		video_init_opengl()

		return true
	}

	_platform_impl_destroy_window = proc() {
		log.debug("Cleaning up GLFW...")
		imgui_glfw.Shutdown()
		glfw.DestroyWindow(_glfw.window)
		_glfw.window = nil
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

	_platform_impl_swap_buffers = proc() {
		if _glfw.video_impl == .OpenGL do glfw.SwapBuffers(_glfw.window)
		if glfw.WindowShouldClose(_glfw.window) {
			handle_graphics_device_lost()
		}
	}

	_platform_impl_is_window_visible = proc() -> bool {
		return _glfw.window != nil && glfw.GetWindowAttrib(_glfw.window, glfw.VISIBLE) != 0
	}
}
