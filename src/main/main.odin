package main

import "core:time"
import "core:log"

import imgui "src:thirdparty/odin-imgui"

import "src:client"
import "src:server"
import "src:sys"
import sys_main "src:sys/main"

@private
g: struct {
	cl: client.Client,
	sv: server.Server,
}

run :: proc() -> bool {
	prev_frame_start: time.Tick

	imgui.CreateContext()
	defer imgui.DestroyContext()

	// Configure ImGui
	{
		io := imgui.GetIO()
		io.ConfigFlags |= {.DockingEnable}
	}

	sys_main.init(&g.sv, &g.cl) or_return
	defer sys_main.shutdown()
	sys_main.create_window() or_return

	server.init(&g.sv, sys_main.post_empty_event, ".", ".") or_return
	client.init(&g.cl, &g.sv, ".", ".", sys_main.post_empty_event) or_return

	sys_main.show_window(true)

	for {
		frame_start := time.tick_now()

		server.handle_events(&g.sv)
		client.handle_events(&g.cl, &g.sv)
		sys_main.handle_events()

		sys_main.new_frame()
		imgui.NewFrame()

		client.frame(&g.cl, &g.sv, prev_frame_start, frame_start)

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

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger()
	}

	run()
}
