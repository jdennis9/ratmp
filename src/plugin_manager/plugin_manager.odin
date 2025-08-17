package plugin_manager

// =============================================================================
// Only developers should care about this
// =============================================================================

import "core:log"
import sa "core:container/small_array"

import imgui "src:thirdparty/odin-imgui"

import "src:client/imx"
import "src:client"
import "src:server"

MAX_PLUGINS :: 32

Plugin_Ctx :: struct {
	client: ^client.Client,
	server: ^server.Server,
}

Plugin_Hooks :: struct {
	init: proc(ctx: Plugin_Ctx),
	frame: proc(ctx: Plugin_Ctx, delta: f32),
	handle_event: proc(ctx: Plugin_Ctx, event: server.Event),
	destroy: proc(ctx: Plugin_Ctx),
}

Plugin_Info :: struct {
	name: string,
	author: string,
	description: string,
	version: struct {major, minor, patch: u32},
}

Plugin_Manager :: struct {
	info: sa.Small_Array(MAX_PLUGINS, Plugin_Info),
	hooks: sa.Small_Array(MAX_PLUGINS, Plugin_Hooks),
	enabled: [MAX_PLUGINS]bool,
	ctx: Plugin_Ctx,
}

Plugin :: struct {
	info: Plugin_Info,
	hooks: Plugin_Hooks,
}

init :: proc(mgr: ^Plugin_Manager, cl: ^client.Client, sv: ^server.Server) {
	mgr.ctx.client = cl
	mgr.ctx.server = sv
}

add :: proc(mgr: ^Plugin_Manager, plugin: Plugin) {
	index := sa.len(mgr.info)
	sa.append(&mgr.info, plugin.info)
	sa.append(&mgr.hooks, plugin.hooks)
	mgr.enabled[index] = true

	log.info("Add plugin", plugin.info.name, plugin.info.version)
}

run_init_hooks :: proc(mgr: ^Plugin_Manager) {
	for hooks, index in sa.slice(&mgr.hooks) {
		if mgr.enabled[index] {
			hooks.init(mgr.ctx)
		}
	}
}

run_frame_hooks :: proc(mgr: ^Plugin_Manager, delta: f32) {
	for hooks, index in sa.slice(&mgr.hooks) {
		if mgr.enabled[index] {
			hooks.frame(mgr.ctx, delta)
		}
	}
}

run_event_hooks :: proc(mgr: ^Plugin_Manager, event: server.Event) {
	for hooks, index in sa.slice(&mgr.hooks) {
		if mgr.enabled[index] {
			hooks.handle_event(mgr.ctx, event)
		}
	}
}

run_destroy_hooks :: proc(mgr: ^Plugin_Manager) {
	for hooks, index in sa.slice(&mgr.hooks) {
		if mgr.enabled[index] {
			hooks.destroy(mgr.ctx)
		}
	}
}

show_imgui_menu :: proc(mgr: ^Plugin_Manager) {
	if !imgui.Begin("Plugins##plugin_manager") {imgui.End(); return}
	defer imgui.End()

	for info, index in sa.slice(&mgr.info) {
		imgui.PushIDInt(auto_cast index)
		defer imgui.PopID()
		imx.text(256, "Name:", info.name)
		imx.text(256, "Author:", info.author)
		imx.text(1024, "Description:", info.description)
		imx.textf(32, "Version: %d.%d.%d", info.version.major, info.version.minor, info.version.patch)
		imgui.Checkbox("Enable", &mgr.enabled[index])
		imgui.Separator()
	}
}
