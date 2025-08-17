package example_plugin

import pl "src:plugin_manager"
import "src:server"
import "src:client"
import imgui "src:thirdparty/odin-imgui"

plugin :: proc() -> (plug: pl.Plugin) {
	plug.hooks = pl.Plugin_Hooks {
		init = init,
		frame = frame,
		handle_event = handle_event,
		destroy = destroy,
	}

	plug.info = pl.Plugin_Info {
		name = "Example",
		description = "My example plugin",
		author = "RAT MP",
		version = {major = 1, minor = 0, patch = 0}
	}

	return
}

@private
init :: proc(ctx: pl.Plugin_Ctx) {
}

@private
frame :: proc(ctx: pl.Plugin_Ctx, delta: f32) {
	if imgui.Begin("Plugin Window") {
		imgui.Text("Hello, RAT MP")
	}
	imgui.End()
}

@private
handle_event :: proc(ctx: pl.Plugin_Ctx, event: server.Event) {
}

@private
destroy :: proc(ctx: pl.Plugin_Ctx) {
}
