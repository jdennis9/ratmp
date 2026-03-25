package main

import "vendor:glfw"
import "core:log"
import imgui "src:thirdparty/odin-imgui"

@(private="file")
GRAPHICS_BACKEND :: Video_Impl.OpenGL

handle_graphics_device_lost :: proc() -> bool {
	log.warn("Graphics device lost, freeing resources and reinitializing...")
	video_destroy()
	platform_destroy()
	platform_init() or_return
	return true
}

@(private="file")
run :: proc() -> bool {
	context.logger = log.create_console_logger()

	server: Server
	ui: UI

	when ODIN_OS == .Windows {
		use_audio_wasapi()
	}
	else {
		use_audio_pulse()
	}

	audio_init(server_audio_callback, &server) or_return
	defer audio_shutdown()
	audio_start() or_return

	server_init(&server) or_return
	defer server_shutdown(&server)

	if .Headless in global_flags {
		return run_headless(&server)
	}
		
	imgui.CreateContext()
	defer imgui.DestroyContext()
	
	when ODIN_OS == .Windows do use_platform_win32()
	else do use_platform_glfw()

	if io := imgui.GetIO(); io != nil {
		io.ConfigFlags |= {.DockingEnable}
	}
	
	platform_init() or_return
	defer platform_destroy()	
	defer video_destroy()
	
	ui_init(&ui, &server) or_return
	defer ui_shutdown(&ui)

	for {
		platform_imgui_new_frame()
		video_imgui_new_frame()
		imgui.NewFrame()
		
		platform_poll_events()
		server_handle_events(&server)

		// Show UI here
		ui_show(&ui)

		imgui.Render()

		video_render_frame()
		
		platform_swap_buffers()
	}

	return true
}

@(private="file")
run_headless :: proc(server: ^Server) -> bool {
	for {
		server_wait_events(server)
	}

	return true
}

main :: proc() {
	run()
}
