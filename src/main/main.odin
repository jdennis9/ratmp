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

import "core:mem"
import "core:time"
import "core:thread"
import "core:os"
import "core:flags"
import "core:log"
import imgui "src:thirdparty/odin-imgui"

_g: struct {
	want_show_window:   bool,
	running:            bool,
	tracking_allocator: mem.Tracking_Allocator,
	logging_allocator:  log.Log_Allocator,
}

get_global_tracking_allocator :: proc() -> mem.Tracking_Allocator {
	return _g.tracking_allocator
}

@(private="file")
run :: proc() -> Error {
	server: Server
	ui: UI

	// --------------------------------------------------------------------------
	// Parse command-line
	// This needs to happen first because it affects many things!
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
	// Set up allocators
	// --------------------------------------------------------------------------
	if command_opts.memory_debug {
		mem.tracking_allocator_init(&_g.tracking_allocator, context.allocator)
	}

	context.allocator = 
		command_opts.memory_debug ? mem.tracking_allocator(&_g.tracking_allocator) : context.allocator

	if command_opts.heap_alloc_log {
		log.log_allocator_init(&_g.logging_allocator, .Debug, .Human, context.allocator)
	}
	
	context.allocator =
		command_opts.heap_alloc_log ? log.log_allocator(&_g.logging_allocator) : context.allocator

	// --------------------------------------------------------------------------
	// Get paths
	// --------------------------------------------------------------------------
	when ODIN_OS == .Linux && !ODIN_DEBUG {
		config_dir := os.user_config_dir(context.allocator) or_return
		data_dir := os.user_data_dir(context.allocator) or_return

		global_paths.config_dir, _ = os.join_path({config_dir, PROGRAM_FOLDER_NAME}, context.allocator)
		global_paths.data_dir, _ = os.join_path({data_dir, PROGRAM_FOLDER_NAME}, context.allocator)

		delete(config_dir)
		delete(data_dir)

		defer delete(global_paths.config_dir)
		defer delete(global_paths.data_dir)
	}
	else {
		global_paths.config_dir = "."
		global_paths.data_dir = "."
	}

	global_paths.settings, _ = os.join_path({global_paths.config_dir, "settings.json"}, context.allocator)

	// --------------------------------------------------------------------------
	// Config
	// --------------------------------------------------------------------------
	{
		config_init_buffers(&global_config)
		config_load(&global_config, global_paths.settings, context.allocator)
	}

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
	library_init()
	defer library_destroy()

	server_init(&server) or_return
	defer server_shutdown(&server)

	library_load_thread := thread.create(_library_load_thread_proc)
	library_load_thread.data = &server
	library_load_thread.init_context = context
	thread.start(library_load_thread)
	
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
			font_init_windows()
			dialog_init_windows()
		}
		else {
			platform_init_glfw() or_return
			font_init_fontconfig() or_return
			notify_init_libnotify()
			dialog_init_gtk()
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

	thread.join(library_load_thread)
	
	ui_init(&ui, &server) or_return
	defer ui_shutdown(&ui)

	if command_opts.profile_startup do return nil

	_g.running = true
	global_delta_time = 1.0/60.0
	
	for _g.running {
		events: Platform_Events
		ui_actions: UI_Actions

		frame_start := time.tick_now()
		sys_main_frame()
		update_async_dialogs()

		if _g.want_show_window {
			_g.want_show_window = false
			platform_set_window_visible(true)
		}

		if global_config_dirty {
			global_config_dirty = false
			config_save(global_config, global_paths.settings)
			if !command_opts.headless {
				ui_apply_config(&ui, global_config)
			}
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
		if ui_actions.debug.save_library {
			library_save(server.paths.library_database)
		}

		if ui_actions.debug.load_library {
			library_load(server.paths.library_database)
		}

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
		global_uptime += time.duration_seconds(frame_time)
		global_delta_time = f32(time.duration_seconds(frame_time))
	}

	return nil
}

@(private="file")
_tray_callback :: proc(data: rawptr, button: Sys_Tray_Button) {
	sv := cast(^Server) data
	switch button {
		case .None:
		case .Show:
			_g.want_show_window = true
		case .Pause: server_request_pause(sv)
		case .Resume: server_request_resume(sv)
		case .Prev: server_request_previous_track(sv)
		case .Next: server_request_next_track(sv)
		case .Exit: _g.running = false
	}
	platform_flush_events()
}

@(private="file")
_media_controls_proc :: proc(data: rawptr, event: Media_Controls_Event) {
	sv := cast(^Server) data

	switch event {
		case .Play:
			server_request_resume(sv)
			if global_config.server.notify_background_playback_state {
				notify_send("Playback resumed")
			}
		case .Toggle:
		case .Pause:
			server_request_pause(sv)
		case .Stop:
		case .Next: server_request_next_track(sv)
		case .Prev: server_request_previous_track(sv)
		case .EnableShuffle: server_set_shuffle_enabled(sv, true)
		case .DisableShuffle: server_set_shuffle_enabled(sv, false)
	}
}

@(private="file")
_library_load_thread_proc :: proc(t: ^thread.Thread) {
	sv := cast(^Server) t.data
	library_load(sv.paths.library_database)
}

main :: proc() {
	context.logger = log.create_console_logger()
	error := run()
	if error != nil {
		log.error("run() exited with error", error)
	}
	else {
		log.info("Program exited succesfully")
	}
}
