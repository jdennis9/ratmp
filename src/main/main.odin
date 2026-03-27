package main

import "core:thread"
import "core:fmt"
import "core:os"
import "core:flags"
import "core:sync"
import "vendor:glfw"
import "core:log"
import imgui "src:thirdparty/odin-imgui"

handle_graphics_device_lost :: proc() -> bool {
	log.warn("Graphics device lost, freeing resources and reinitializing...")
	platform_destroy_window()
	platform_make_window() or_return
	return true
}

_g: struct {
	want_show_window: bool,
}

@(private="file")
run :: proc() -> bool {
	context.logger = log.create_console_logger()

	server: Server
	ui: UI
	command_opts: struct {
		headless: bool `usage:"Run without UI."`,
		no_media_controls: bool `usage:"Don't use system media controls."`,
		force_opengl: bool `usage:"(Windows) Force using OpenGL if DX11 is not supported on your device."`,
	}

	// --------------------------------------------------------------------------
	// Parse command-line
	// --------------------------------------------------------------------------
	if len(os.args) > 1 {
		error := flags.parse(&command_opts, os.args[1:])

		switch e in error {
		case flags.Help_Request:
			flags.write_usage(os.to_writer(os.stdout), type_of(command_opts), "RATMP")
			return true
		case flags.Parse_Error, flags.Open_File_Error, flags.Validation_Error:
			log.error(error)
			return false
		}
	}

	// --------------------------------------------------------------------------
	// Audio
	// --------------------------------------------------------------------------
	when ODIN_OS == .Windows {
		use_audio_wasapi()
	}
	else {
		use_audio_pulse()
	}
	
	audio_init(server_audio_callback, &server) or_return
	defer audio_shutdown()
	audio_start() or_return
	
	// --------------------------------------------------------------------------
	// Server
	// --------------------------------------------------------------------------
	server_init(&server) or_return
	defer server_shutdown(&server)
	
	// --------------------------------------------------------------------------
	// ImGui
	// --------------------------------------------------------------------------
	imgui.CreateContext()
	defer imgui.DestroyContext()
	log.debug("ImGui version:", imgui.GetVersion())
	
	if io := imgui.GetIO(); io != nil {
		io.ConfigFlags |= {.DockingEnable}
	}
	
	// --------------------------------------------------------------------------
	// Platform
	// --------------------------------------------------------------------------
	sys_main_init() or_return
	defer sys_main_shutdown()

	if command_opts.headless {
		platform_init_null()
	}
	else {
		when ODIN_OS == .Windows {
			platform_init_win32() or_return
		}
		else {
			platform_init_glfw() or_return
		}
	}

	// --------------------------------------------------------------------------
	// System tray
	// --------------------------------------------------------------------------
	when ODIN_OS == .Windows {
		systray_use_win32()
	}
	else {
		systray_use_linux_appindicator()
	}
	
	systray_create(_tray_callback, &server)
	defer systray_destroy()

	platform_make_window() or_return

	defer {
		platform_destroy_window()
		platform_shutdown()
	}
	
	ui_init(&ui, &server) or_return
	defer ui_shutdown(&ui)

	for {
		events: Platform_Events

		if _g.want_show_window {
			_g.want_show_window = false
			platform_set_window_visible(true)
		}

		if platform_is_window_visible() {
			platform_imgui_new_frame()
			video_imgui_new_frame()
			imgui.NewFrame()
			
			server_handle_events(&server)
			events = platform_poll_events()

			ui_show(&ui)

			imgui.Render()
			video_render_frame()
			platform_swap_buffers()
		}
		else {
			events = platform_wait_events()
			server_handle_events(&server)
		}

		if events.window_closed {
			platform_set_window_visible(false)
		}
	}

	return true
}

@(private="file")
_tray_callback :: proc(data: rawptr, button: Sys_Tray_Button) {
	sv := cast(^Server) data
	switch button {
		case .Show:
			_g.want_show_window = true
			platform_flush_events()
		case .Pause: server_request_pause(sv)
		case .Resume: server_request_resume(sv)
		case .Prev: server_request_previous_track(sv)
		case .Next: server_request_next_track(sv)
		case .Exit:
	}
}

main :: proc() {
	run()
}
