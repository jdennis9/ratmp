package example_plugin

import "core:log"
import "core:math/linalg"

import "../sdk"
import imgui "../src/thirdparty/odin-imgui"

BAND_COUNT :: 24

library: ^sdk.Library_Procs
draw: ^sdk.Draw_Procs
ui: ^sdk.UI_Procs
analysis: ^sdk.Analysis_Procs
playback: ^sdk.Playback_Procs

state: struct {
	band_frequencies: [BAND_COUNT]f32,
	band_peaks: [BAND_COUNT]f32,
	peak: f32,
	fft: sdk.FFT_State
}

// =============================================================================
// Required

// Called when the plugin is loaded. Pointers to the SDK functions are passed in
@export @(link_name="plug_load")
plug_load :: proc(procs: sdk.SDK) -> (info: sdk.Plugin_Info) {
	draw = procs.draw
	ui = procs.ui
	analysis = procs.analysis
	playback = procs.playback
	library = procs.library

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

	analysis.distribute_spectrum_frequencies(state.band_frequencies[:])
	state.fft = analysis.fft_new_state(12000)
}

// Called every frame. Previous frame length is passed in
@export @(link_name="plug_frame")
plug_frame :: proc(delta_time: f32) {
	if ui.begin("My Plugin Window") {
		drawlist := ui.get_window_drawlist()
		pos := ui.get_cursor()
		draw.rect_filled(drawlist, pos, pos + {64, 64}, 0xff00ffff, 4)
		ui.dummy({64, 64})

		ui.text("Hello, world!")

		ui.text("Peak:", state.peak)
		for i in 0..<len(state.band_frequencies) {
			ui.text(state.band_frequencies[i], state.band_peaks[i])
		}

		if ui.button("Pause") {
			playback.toggle_paused()
		}
		if ui.button("Restart") {
			playback.seek_to_second(0)
		}

		ui.end()
	}
}

@export @(link_name="plug_analyse")
plug_analyse :: proc(audio: [][]f32, fft: []f32, samplerate: int, delta: f32) {
	peak: f32

	for sample in audio[0] {
		peak = max(peak, sample)
	}

	for &bp in state.band_peaks do bp = 0

	state.peak = linalg.lerp(state.peak, peak, delta * 5)
	analysis.fft_extract_bands(fft, len(audio[0]), state.band_frequencies[:], f32(samplerate), state.band_peaks[:])
}

@export @(link_name="plug_post_process")
plug_post_process :: proc(audio: []f32, samplerate, channels: int) {
	for &s in audio {
		s = clamp(s, -1, 1)
	}
}

// Called when track is changed
@export @(link_name="plug_on_track_changed")
plug_on_track_changed :: proc(track: sdk.Track_ID) {}

// Called when playback state is changed
@export @(link_name="plug_on_playback_state_changed")
plug_on_playback_state_changed :: proc(new_state: sdk.Playback_State) {}