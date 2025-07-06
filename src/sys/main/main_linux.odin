package sys_main

import "base:runtime"

import "vendor:glfw"

import imgui_glfw "src:thirdparty/odin-imgui/imgui_impl_glfw"
import imgui_gl "src:thirdparty/odin-imgui/imgui_impl_opengl3"

import "src:build"
import "src:server"
import "src:client"
import "src:sys"

@private
_linux: struct {
	ctx: runtime.Context,
	window: glfw.WindowHandle,
	running: bool,
	sv: ^server.Server,
	cl: ^client.Client,
}

init :: proc(sv: ^server.Server, cl: ^client.Client) -> bool {
	_linux.sv = sv
	_linux.cl = cl
	_linux.ctx = context
	return true
}

create_window :: proc() -> bool {
	glfw.Init()

	_linux.window = glfw.CreateWindow(1600, 900, build.PROGRAM_NAME_AND_VERSION, nil, nil)
	if _linux.window == nil {return false}
	glfw.MakeContextCurrent(_linux.window)

	sys._gl_init(_linux.window)

	imgui_glfw.InitForOpenGL(_linux.window, true)
	imgui_gl.Init()

	_linux.running = true

	return true
}

present :: proc() {
	glfw.SwapBuffers(_linux.window)
}

shutdown :: proc() {
	glfw.DestroyWindow(_linux.window)
	imgui_gl.Shutdown()
	imgui_glfw.Shutdown()
}

new_frame :: proc() {
	sys._gl_clear_buffer()

	imgui_glfw.NewFrame()
	imgui_gl.NewFrame()
}

// Return false to terminate program
handle_events :: proc() -> bool {
	glfw.PollEvents()
	return _linux.running
}

show_window :: proc(show: bool) {
	if show {
		glfw.ShowWindow(_linux.window)
	}
	else {
		glfw.HideWindow(_linux.window)
	}
}

post_empty_event :: proc() {
	glfw.PostEmptyEvent()
}

set_window_title :: proc(title: string) {
	buf: [256]u8
	copy(buf[:255], title)
	glfw.SetWindowTitle(_linux.window, cstring(&buf[0]))
}
