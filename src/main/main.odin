package main

import "core:sync"
import "vendor:glfw"
import "core:log"
import imgui "src:thirdparty/odin-imgui"

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
		systray_use_windows()
	}
	else {
		use_audio_pulse()
		systray_use_linux_appindicator()
	}

	audio_init(server_audio_callback, &server) or_return
	defer audio_shutdown()
	audio_start() or_return

	server_init(&server) or_return
	defer server_shutdown(&server)

	if .Headless in global_flags {
		return run_headless(&server)
	}

	sys_main_init() or_return
	defer sys_main_shutdown()
		
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

	systray_create(_tray_callback, &server)
	defer systray_destroy()

	for {
		sys_main_frame()

		if platform_is_window_visible() {
			platform_imgui_new_frame()
			video_imgui_new_frame()
			imgui.NewFrame()
			
			server_handle_events(&server)
			platform_poll_events()

			// Show UI here
			ui_show(&ui)

			imgui.Render()

			video_render_frame()
			
			platform_swap_buffers()
		}
		else {
			server_wait_events(&server)
		}
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

@(private="file")
_tray_callback :: proc(data: rawptr, button: Sys_Tray_Button) {
}

main :: proc() {
	run()
}
