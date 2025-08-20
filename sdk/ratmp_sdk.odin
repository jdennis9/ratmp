package ratmp_sdk

/*
Procedures to define (copy+paste this into a file to use as a base):

// =============================================================================
// Required

// Called when the plugin is loaded. Pointers to the SDK functions are passed in.
// Filled in Plugin_Info struct needs to be returned
@export @(link_name="plug_load")
plug_load :: proc(lib: sdk.SDK) -> (info: sdk.Plugin_Info) {
	return
}

// =============================================================================
// Optional

// Called before main loop starts
@export @(link_name="plug_init")
plug_init :: proc() {}

// Called every frame. Previous frame length is passed in
@export @(link_name="plug_frame")
plug_frame :: proc(delta_time: f32) {}

@export @(link_name="plug_analyse")
plug_analyse :: proc(audio: [][]f32, samplerate: int, delta: f32) {}

@export @(link_name="plug_analyse_spectrum")
plug_analyse_spectrum :: proc(spectrum: []f32, samplerate: int, delta: f32) {}

// Called when track is changed
@export @(link_name="plug_on_track_changed")
plug_on_track_changed :: proc(track: sdk.Track_ID) {}

// Called when playback state is changed
@export @(link_name="plug_on_playback_state_changed")
plug_on_playback_state_changed :: proc(new_state: sdk.Playback_State) {}

*/

Load_Proc :: #type proc(lib: SDK) -> Plugin_Info
Init_Proc :: #type proc()
Frame_Proc :: #type proc(delta: f32)
Analyse_Proc :: #type proc(audio: [][]f32, samplerate: int, delta: f32)
Analyse_Spectrum_Proc :: #type proc(spectrum: []Spectrum_Band, samplerate: int, delta: f32)
On_Track_Changed_Proc :: #type proc(track: Track_ID)
On_Playback_State_Changed_Proc :: #type proc(new_state: Playback_State)

Version :: struct {major, minor, patch: int}
Track_ID :: distinct u32
Playback_State :: enum {Playing, Paused, Stopped}

Rect :: struct {
	pmin, pmax: [2]f32,
}

SDK :: struct {
	version: proc() -> Version,
	get_playing_track_id: proc() -> Track_ID,

	ui_get_cursor: proc() -> [2]f32,
	ui_begin: proc(str_id: cstring, p_open: ^bool = nil) -> bool,
	ui_end: proc(),
	ui_dummy: proc(size: [2]f32),
	ui_invisible_button: proc(str_id: cstring, size: [2]f32) -> bool,
	ui_text_unformatted: proc(str: string),
	ui_text: proc(args: ..any),
	ui_textf: proc(format: string, args: ..any),
	ui_button: proc(label: cstring) -> bool,
	ui_selectable: proc(label: cstring, selected: bool) -> bool,
	ui_toggleable: proc(label: cstring, selected: ^bool) -> bool,
	ui_checkbox: proc(label: cstring, value: ^bool) -> bool,
	ui_begin_combo: proc(label: cstring, preview: cstring) -> bool,
	ui_end_combo: proc(),

	draw_rect: proc(pmin, pmax: [2]f32, color: u32, thickness: f32 = 0, rounding: f32 = 0),
	draw_rect_filled: proc(pmin, pmax: [2]f32, color: u32, rounding: f32 = 0),
	draw_many_rects: proc(rects: []Rect, colors: []u32, thickness: f32 = 0, rounding: f32 = 0),
	draw_many_rects_filled: proc(rects: []Rect, colors: []u32, rounding: f32 = 0),

	// Distribute frequencies naturally
	analysis_distribute_spectrum_frequencies: proc(out: []f32),
	// Calculates FFT and distributes values into bands based on freq_cutoffs input.
	// It's recommended to use this with the same input size, output size and frequency cutoffs
	// between calls for optimal performance
	analysis_calc_spectrum: proc(input: []f32, freq_cutoffs: []f32, output: []f32),
}

Plugin_Info :: struct {
	name: string,
	author: string,
	description: string,
	version: Version,
}

Track_Metadata :: struct {
	title, album, artist, genre: string,
	duration_seconds: i64,
	unix_file_date: i64,
	unix_added_date: i64,
}

Spectrum_Band :: struct {
	freq: f32,
	peak: f32,
}
