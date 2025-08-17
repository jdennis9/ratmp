package main

import "core:time"
import "core:log"
import "core:fmt"
import "core:os"

import "src:bindings/ffmpeg"
import imgui "src:thirdparty/odin-imgui"

import "src:build"
import "src:client"
import "src:server"
import "src:sys"
import plugin "src:plugin_manager"
import plugin_setup "src:plugins"
import sys_main "src:sys/main"

@private
g: struct {
	cl: client.Client,
	sv: server.Server,
	plugins: plugin.Plugin_Manager,
	title_track_id: server.Track_ID,
}

USAGE :: `
Options:

-h, --help, -help, /?: Show this message
-no-plugins: Disable plugins
`

run :: proc() -> bool {
	prev_frame_start: time.Tick
	enable_plugins := true

	for arg in os.args {
		if arg == "-h" || arg == "--help" || arg == "/?" || arg == "-help" {
			fmt.println(USAGE)
			return false
		}

		if arg == "-no-plugins" {
			enable_plugins = false
		}
	}

	imgui.CreateContext()
	defer imgui.DestroyContext()

	log.info("AVCodec license: ", ffmpeg.codec_license())

	// Configure ImGui
	{
		io := imgui.GetIO()
		io.ConfigFlags |= {.DockingEnable}
	}

	sys_main.init(&g.sv, &g.cl) or_return
	defer sys_main.shutdown()
	sys_main.create_window() or_return

	server.init(&g.sv, sys_main.post_empty_event, ".", ".") or_return
	defer server.clean_up(&g.sv)
	client.init(&g.cl, &g.sv, ".", ".", sys_main.post_empty_event) or_return
	defer client.destroy(&g.cl)

	if enable_plugins {
		plugin.init(&g.plugins, &g.cl, &g.sv)
		plugin_setup.add(&g.plugins)
		plugin.run_init_hooks(&g.plugins)
	}
	
	server.add_event_handler(&g.sv, server_event_handler, nil)
	
	sys_main.show_window(true)

	for {
		frame_start := time.tick_now()

		server.handle_events(&g.sv)
		client.handle_events(&g.cl, &g.sv)
		if !sys_main.handle_events() {break}

		sys_main.new_frame()
		imgui.NewFrame()

		delta := client.frame(&g.cl, &g.sv, prev_frame_start, frame_start)
		plugin.run_frame_hooks(&g.plugins, delta)
		plugin.show_imgui_menu(&g.plugins)

		imgui.Render()
		draw_data := imgui.GetDrawData()
		if draw_data != nil {
			sys.imgui_render_draw_data(draw_data)
		}
		sys_main.present()

		imgui.FontAtlas_ClearTexData(imgui.GetIO().Fonts)
		imgui.FontAtlas_ClearInputData(imgui.GetIO().Fonts)

		prev_frame_start = frame_start

		if g.cl.want_quit {
			break
		}
	}

	plugin.run_destroy_hooks(&g.plugins)

	return true
}

server_event_handler :: proc(sv: server.Server, data: rawptr, event: server.Event) {
	#partial switch v in event {
		case server.Current_Track_Changed_Event: {
			if g.title_track_id != v.track_id {
				g.title_track_id = v.track_id
				if md, track_found := server.library_get_track_metadata(sv.library, v.track_id); track_found {
					buf: [256]u8
					title := fmt.bprint(buf[:255], build.PROGRAM_NAME_AND_VERSION, "|",
						md.values[.Artist].(string) or_else "",
						"-",
						md.values[.Title].(string) or_else ""
					)
					sys_main.set_window_title(title)
				}
			}
		}
	}

	plugin.run_event_hooks(&g.plugins, event)
}

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger()
	}
	else {
		context.logger = log.create_console_logger(.Info)
	}

	run()
}
