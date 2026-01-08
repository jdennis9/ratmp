package ratmp_sdk

import "core:mem"
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

// Called every frame. Previous frame duration is passed in
@export @(link_name="plug_frame")
plug_frame :: proc(delta_time: f32) {}

// Called every frame. Audio passed in is already windowed and is synced with current output time
@export @(link_name="plug_analyse")
plug_analyse :: proc(audio: [][]f32, samplerate: int, delta: f32) {}

// Use to process audio buffer after decoding and before sending to output
@export @(link_name="plug_post_process")
plug_post_process :: proc(audio: []f32, samplerate, channels: int) {}

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
Analyse_Proc :: #type proc(audio: [][]f32, fft: []f32, samplerate: int, delta: f32)
Post_Process_Proc :: #type proc(audio: []f32, samplerate, channels: int)
On_Track_Changed_Proc :: #type proc(track: Track_ID)
On_Playback_State_Changed_Proc :: #type proc(new_state: Playback_State)

Version :: struct {major, minor, patch: int}
Track_ID :: distinct u32
Playback_State :: enum {Playing, Paused, Stopped}
Texture_ID :: distinct uintptr
Draw_List :: distinct rawptr

Rect :: struct {
	min, max: [2]f32,
}

Base_Procs :: struct {
	version: proc() -> Version,
}

UI_Procs :: struct {
	get_cursor: proc() -> [2]f32,
	begin: proc(str_id: cstring, p_open: ^bool = nil) -> bool,
	end: proc(),
	dummy: proc(size: [2]f32),
	invisible_button: proc(str_id: cstring, size: [2]f32) -> bool,
	text_unformatted: proc(str: string),
	text: proc(args: ..any),
	textf: proc(format: string, args: ..any),
	button: proc(label: cstring) -> bool,
	selectable: proc(label: cstring, selected: bool) -> bool,
	toggleable: proc(label: cstring, selected: ^bool) -> bool,
	checkbox: proc(label: cstring, value: ^bool) -> bool,
	begin_combo: proc(label: cstring, preview: cstring) -> bool,
	end_combo: proc(),
	get_window_drawlist: proc() -> Draw_List,
}

Draw_Procs :: struct {
	rect: proc(drawlist: Draw_List, pmin, pmax: [2]f32, color: u32, thickness: f32 = 0, rounding: f32 = 0),
	rect_filled: proc(drawlist: Draw_List, pmin, pmax: [2]f32, color: u32, rounding: f32 = 0),
	many_rects: proc(drawlist: Draw_List, rects: []Rect, colors: []u32, thickness: f32 = 0, rounding: f32 = 0),
	many_rects_filled: proc(drawlist: Draw_List, rects: []Rect, colors: []u32, rounding: f32 = 0),
}

Analysis_Procs :: struct {
	distribute_spectrum_frequencies: proc(out: []f32),
	fft_new_state: proc(window_size: int) -> FFT_State,
	fft_destroy_state: proc(state: FFT_State),
	fft_set_window_size: proc(state: FFT_State, size: int),
	fft_process: proc(state: FFT_State, input: []f32) -> []f32,
	fft_extract_bands: proc(fft: []f32, input_frames: int, freq_cutoffs: []f32, samplerate: f32, output: []f32),
}

Playback_Procs :: struct {
	is_paused: proc() -> bool,
	set_paused: proc(paused: bool),
	toggle_paused: proc(),
	get_track_duration_seconds: proc() -> int,
	seek_to_second: proc(second: int),
	get_playing_track_id: proc() -> Track_ID,
}

Library_Procs :: struct {
	lookup_track: proc(id: Track_ID) -> (index: int, found: bool),
	get_track_metadata: proc(index: int, md: ^Track_Metadata),
	get_track_cover_art: proc(index: int) -> (texture: Texture_ID, ok: bool),
}

SDK :: struct {
	ui: ^UI_Procs,
	draw: ^Draw_Procs,
	analysis: ^Analysis_Procs,
	playback: ^Playback_Procs,
	library: ^Library_Procs,
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

FFT_State :: distinct rawptr
