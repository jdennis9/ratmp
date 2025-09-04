/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

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
import sys_main "src:sys/main"

@private
g: struct {
	cl: client.Client,
	sv: server.Server,
	plugin_manager: Plugin_Manager,
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

	// Set SDK proc addresses
	sdk_init(&g.cl, &g.sv)
	if enable_plugins {
		plugins_load(&g.plugin_manager, "Plugins")
	}
	
	server.add_event_handler(&g.sv, server_event_handler, nil)

	plugins_init_all(&g.plugin_manager)
	server.add_post_process_hook(&g.sv, plugins_post_process, &g.plugin_manager)
	sys_main.show_window(true)

	for {
		frame_start := time.tick_now()

		server.handle_events(&g.sv)
		client.handle_events(&g.cl, &g.sv)
		if !sys_main.handle_events() {break}
		
		sys_main.new_frame()
		imgui.NewFrame()
		
		delta := client.frame(&g.cl, &g.sv, prev_frame_start, frame_start)
		if enable_plugins {
			sdk_frame()
			plugins_frame(&g.plugin_manager, &g.cl, &g.sv, delta)
		}

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


