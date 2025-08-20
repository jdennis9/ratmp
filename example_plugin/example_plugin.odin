package example_plugin

import "core:log"
import "core:math/linalg"

import "../sdk"
import imgui "../src/thirdparty/odin-imgui"

// =============================================================================
// Required

api: sdk.SDK
ui: ^sdk.UI_Procs
draw: ^sdk.Draw_Procs

// Called when the plugin is loaded. Pointers to the SDK functions are passed in
@export @(link_name="plug_load")
plug_load :: proc(lib: sdk.SDK) -> (info: sdk.Plugin_Info) {
	api = lib
	ui = &api.ui
	draw = &api.draw

	info.name = "Example"
	info.author = "RAT MP"
	info.description = "Example plugin for RAT MP"
	info.version = {0, 1, 0}

	return
}

// =============================================================================
// Optional

// Called before main loop starts
@export @(link_name="plug_init")
plug_init :: proc() {
	log.info("****** Initialising example plugin ******")
}

// Called every frame. Previous frame length is passed in
@export @(link_name="plug_frame")
plug_frame :: proc(delta_time: f32) {
	if ui.begin("My Plugin Window") {
		pos := ui.get_cursor()
		draw.rect_filled(pos, pos + {64, 64}, 0xff00ffff, 4)
		ui.dummy({64, 64})

		ui.text("Hello, world!")
		ui.end()
	}
}

@export @(link_name="plug_analyse")
plug_analyse :: proc(audio: [][]f32, samplerate: int, delta: f32) {
	@static smooth_peak: f32
	peak: f32

	for sample in audio[0] {
		peak = max(peak, sample)
	}

	smooth_peak = linalg.lerp(smooth_peak, peak, delta * 5)

	if ui.begin("My Plugin Window") {
		ui.text("Peak:", smooth_peak)
		ui.end()
	}
}

@export @(link_name="plug_analyse_spectrum")
plug_analyse_spectrum :: proc(spectrum: []sdk.Spectrum_Band, samplerate: int, delta: f32) {
	if ui.begin("My Plugin Window") {
		for p in spectrum {
			ui.text(p.freq, p.peak)
		}
		ui.end()
	}
}

// Called when track is changed
@export @(link_name="plug_on_track_changed")
plug_on_track_changed :: proc(track: sdk.Track_ID) {}

// Called when playback state is changed
@export @(link_name="plug_on_playback_state_changed")
plug_on_playback_state_changed :: proc(new_state: sdk.Playback_State) {}