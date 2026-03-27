package main

import "core:time"
import "core:thread"
import "core:fmt"
import "core:os"
import "core:flags"
import "core:sync"
import "vendor:glfw"
import "core:log"
import imgui "src:thirdparty/odin-imgui"

_g: struct {
	want_show_window: bool,
}

@(private="file")
run :: proc() -> bool {
	context.logger = log.create_console_logger()

	server: Server
	ui: UI

	// --------------------------------------------------------------------------
	// Parse command-line
	// --------------------------------------------------------------------------
	if len(os.args) > 1 {
		error := flags.parse(&global_command_opts, os.args[1:])
		
		switch e in error {
		case flags.Help_Request:
			flags.write_usage(os.to_writer(os.stdout), type_of(global_command_opts), "RATMP")
			return true
		case flags.Parse_Error, flags.Open_File_Error, flags.Validation_Error:
			log.error(error)
			return false
		}
	}

	command_opts := global_command_opts

	// --------------------------------------------------------------------------
	// Audio
	// --------------------------------------------------------------------------
	if !command_opts.no_audio {
		when ODIN_OS == .Windows {
			use_audio_wasapi()
		}
		else {
			use_audio_pulse()
		}
	}
	else {
		audio_use_null()
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
	if !command_opts.no_tray {
		when ODIN_OS == .Windows {
			systray_use_win32()
		}
		else {
			systray_use_linux_appindicator()
		}
	}

	systray_create(_tray_callback, &server)
	defer systray_destroy()
	
	// --------------------------------------------------------------------------
	// Media controls
	// --------------------------------------------------------------------------
	if !command_opts.no_media_controls {
		when ODIN_OS == .Windows {
			media_controls_use_smtc()
		}
		else {
			media_controls_use_dbus()
		}
	}

	media_controls_init(_media_controls_proc, &server)
	defer media_controls_destroy()

	platform_make_window() or_return

	defer {
		platform_destroy_window()
		platform_shutdown()
	}
	
	ui_init(&ui, &server) or_return
	defer ui_shutdown(&ui)

	for {
		events: Platform_Events
		ui_actions: UI_Actions

		frame_start := time.tick_now()

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

			ui_actions = ui_show(&ui)

			imgui.Render()
			video_render_frame()
			platform_swap_buffers()
		}
		else {
			events = platform_wait_events()
			server_handle_events(&server)
		}

		// -----------------------------------------------------------------------
		// Handle platform events
		// -----------------------------------------------------------------------
		if events.window_closed {
			platform_set_window_visible(false)
		}
		
		// -----------------------------------------------------------------------
		// Handle UI actions
		// -----------------------------------------------------------------------
		if ui_actions.debug.force_device_reset {
			handle_graphics_device_lost()
		}

		if ui_actions.minimize_to_tray {
			platform_set_window_visible(false)
		}
		
		if ui_actions.exit {
			break
		}

		frame_time := time.tick_diff(frame_start, time.tick_now())
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

@(private="file")
_media_controls_proc :: proc(data: rawptr, event: Media_Controls_Event) {
	sv := cast(^Server) data

	switch event {
		case .Play: server_request_resume(sv)
		case .Toggle:
		case .Pause: server_request_pause(sv)
		case .Stop:
		case .Next: server_request_next_track(sv)
		case .Prev: server_request_previous_track(sv)
		case .EnableShuffle: server_set_shuffle_enabled(sv, true)
		case .DisableShuffle: server_set_shuffle_enabled(sv, false)
	}
}

main :: proc() {
	run()
}
