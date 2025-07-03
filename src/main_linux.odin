package main

import "core:log"
import "core:time"

import "vendor:glfw"
import gl "vendor:OpenGL"

import imgui "src:thirdparty/odin-imgui"
import imgui_glfw "src:thirdparty/odin-imgui/imgui_impl_glfw"
import imgui_gl "src:thirdparty/odin-imgui/imgui_impl_opengl3"

import "src:client"
import "src:server"
import "src:build"

_linux: struct {
	window: glfw.WindowHandle,
}

cl: client.Client
sv: server.Server

wake_proc :: proc() {
	glfw.PostEmptyEvent()
}

run :: proc() -> bool {
	glfw.Init() or_return
	defer glfw.Terminate()

	_linux.window = glfw.CreateWindow(1600, 900, build.PROGRAM_NAME_AND_VERSION, nil, nil)
	if _linux.window == nil {
		log.error("Failed to create window")
		return false
	}
	defer glfw.DestroyWindow(_linux.window)

	glfw.ShowWindow(_linux.window)
	glfw.MakeContextCurrent(_linux.window)
	gl.load_up_to(3, 0, glfw.gl_set_proc_address)

	// Imgui
	imgui.CreateContext()
	defer imgui.DestroyContext()

	// Server & client
	server.init(&sv, wake_proc, ".", ".") or_return
	defer server.clean_up(&sv)
	client.init(&cl, &sv, create_texture_proc, destroy_texture_proc, ".", ".", wake_proc) or_return
	defer client.destroy(&cl)

	{
		folder: server.Path
		copy(folder[:len(folder)-1], "/mnt/storage/Media/Music/Fantasy")
		server.queue_files_for_scanning(&sv, {folder})
	}

	// Load fonts
	load_fonts(1)

	// ImGui backend
	imgui_glfw.InitForOpenGL(_linux.window, true) or_return
	defer imgui_glfw.Shutdown()
	imgui_gl.Init() or_return
	defer imgui_gl.Shutdown()

	prev_frame_start: time.Tick

	for !glfw.WindowShouldClose(_linux.window) {
		frame_start := time.tick_now()

		glfw.PollEvents()
		server.handle_events(&sv)
		client.handle_events(&cl, &sv)

		imgui_glfw.NewFrame()
		imgui_gl.NewFrame()
		imgui.NewFrame()

		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		client.frame(&cl, &sv, prev_frame_start, frame_start)
		
		imgui.Render()
		draw_data := imgui.GetDrawData()
		if draw_data != nil {
			imgui_gl.RenderDrawData(draw_data)
		}

		glfw.SwapBuffers(_linux.window)
		prev_frame_start = frame_start
	}

	return true
}

load_fonts :: proc(scale: f32) {
	client.load_fonts(
		&cl,
		[]client.Load_Font {
			{
				data = #load("data/FontAwesome.otf"),
				size = 11 * scale,
				languages = {.Icons},
			},
		}
	)
}

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger()
	}

	run()
}

create_texture_proc :: proc(data: rawptr, width, height: int) -> (tex: imgui.TextureID, ok: bool) {
	return nil, false
}

destroy_texture_proc :: proc(tex: imgui.TextureID) {
}
