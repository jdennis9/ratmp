package main

import "core:dynlib"
import "core:os/os2"
import "core:strings"
import "core:log"
import "core:sync"

import imgui "src:thirdparty/odin-imgui"

import "src:client"
import "src:client/imx"
import "src:server"

import "src:../sdk"

Plugin :: struct {
	info: sdk.Plugin_Info,
	lib: dynlib.Library,
	enabled: bool,

	procs: struct {
		load: sdk.Load_Proc,
		init: sdk.Init_Proc,
		frame: sdk.Frame_Proc,
		analyse: sdk.Analyse_Proc,
		post_process: sdk.Post_Process_Proc,
	},
}

Plugin_Manager :: struct {
	plugins: [dynamic]Plugin,
	open_ui: bool,
}

plugins_post_process :: proc(data: rawptr, audio: []f32, samplerate, channels: int) {
	mgr := cast(^Plugin_Manager)data

	for plugin in mgr.plugins {
		if plugin.procs.post_process != nil && plugin.enabled {
			plugin.procs.post_process(audio, samplerate, channels)
		}
	}
}

plugins_load :: proc(mgr: ^Plugin_Manager, path: string) {
	files, error := os2.read_directory_by_path(path, -1, context.allocator)
	if error != nil {log.error(error); return}
	defer os2.file_info_slice_delete(files, context.allocator)

	for file in files {
		plugin: Plugin
		plugin.enabled = true
		ok := false

		log.debug(file.fullpath)

		when ODIN_OS == .Windows {
			if !strings.ends_with(file.name, ".dll") {continue}
		}
		else {
			if !strings.ends_with(file.name, ".so") {continue}
		}

		plugin.lib = dynlib.load_library(file.fullpath) or_continue
		defer if !ok {dynlib.unload_library(plugin.lib)}

		plugin.procs.load = auto_cast dynlib.symbol_address(plugin.lib, "plug_load")
		if plugin.procs.load == nil {
			log.error("Plugin", file.name, "does not define plug_load proc, skipping...")
			continue
		}

		plugin.procs.init = auto_cast dynlib.symbol_address(plugin.lib, "plug_init")
		plugin.procs.frame = auto_cast dynlib.symbol_address(plugin.lib, "plug_frame")
		plugin.procs.analyse = auto_cast dynlib.symbol_address(plugin.lib, "plug_analyse")
		plugin.procs.post_process = auto_cast dynlib.symbol_address(plugin.lib, "plug_post_process")

		plugin.info = plugin.procs.load(sdk_procs)
		append(&mgr.plugins, plugin)
		ok = true
	}
}

plugins_init_all :: proc(mgr: ^Plugin_Manager) {
	for plugin in mgr.plugins {
		if plugin.procs.init != nil && plugin.enabled {
			plugin.procs.init()
		}
	}
}

plugins_frame :: proc(mgr: ^Plugin_Manager, cl: ^client.Client, sv: ^server.Server, delta: f32) {
	if imgui.Begin("Plugin Manager", &mgr.open_ui) {
		for &plugin in mgr.plugins {
			info := plugin.info
			hooks := plugin.procs
			imx.text(256, "Name:", info.name)
			imx.text(256, "By:", info.author)
			imx.text(2048, "Description:", info.description)
			imgui.Checkbox("Enable", &plugin.enabled)
			imgui.Separator()
		}
	}
	imgui.End()

	// Analysis
	if cl.analysis.channels != 0 {
		spectrum: [len(cl.analysis.spectrum)]sdk.Spectrum_Band

		for &band, i in spectrum[:cl.analysis.spectrum_frequency_bands_calculated] {
			band.freq = cl.analysis.spectrum_frequencies[i]
			band.peak = cl.analysis.spectrum[i]
		}

		for plugin in mgr.plugins {
			if !plugin.enabled {continue}

			audio: [server.MAX_OUTPUT_CHANNELS][]f32
			for ch in 0..<server.MAX_OUTPUT_CHANNELS {
				audio[ch] = cl.analysis.window_data[ch][:]
			}

			if plugin.procs.analyse != nil {
				plugin.procs.analyse(audio[:cl.analysis.channels], cl.analysis.samplerate, delta)
			}
		}
	}

	for plugin in mgr.plugins {
		if plugin.procs.frame != nil && plugin.enabled {
			plugin.procs.frame(delta)
		}
	}
}
