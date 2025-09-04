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
#+private file
package main

import "core:hash/xxhash"
import "core:slice"
import "core:log"

import imgui "src:thirdparty/odin-imgui"

import "src:client"
import "src:client/imx"
import "src:server"
import "src:analysis"
import "src:../sdk"

Spectrum_Analyser_Settings :: struct {
	window_size: int,
	output_size: u32,
	freq_cutoff_hash: u32,
}

Spectrum_Analyser :: struct {
	state: analysis.Spectrum_Analyser,
	output: []f32,
	calculated: bool,
}

ctx: struct {
	cl: ^client.Client,
	sv: ^server.Server,
	drawlist: ^imgui.DrawList,
	spectrum_analysers: map[Spectrum_Analyser_Settings]Spectrum_Analyser,
}

@private sdk_procs: sdk.SDK
@private sdk_ui_procs: sdk.UI_Procs
@private sdk_draw_procs: sdk.Draw_Procs
@private sdk_helper_procs: sdk.Helper_Procs
@private sdk_playback_procs: sdk.Playback_Procs
@private sdk_library_procs: sdk.Library_Procs

_sdk_version :: proc() -> sdk.Version {
	return {0, 1, 0}
}
_get_playing_track_id :: proc() -> sdk.Track_ID {
	return auto_cast ctx.sv.current_track_id
}

_ui_get_cursor :: proc() -> [2]f32 {
	return imgui.GetCursorScreenPos()
}
_ui_begin :: proc(str_id: cstring, p_open: ^bool) -> bool {
	if imgui.Begin(str_id, p_open) {
		ctx.drawlist = imgui.GetWindowDrawList()
		return true
	}
	else {
		imgui.End()
		return false
	}
}
_ui_end :: proc() {
	imgui.End()
}
_ui_dummy :: proc(size: [2]f32) {
	imgui.Dummy(size)
}
_ui_invisible_button :: proc(str_id: cstring, size: [2]f32) -> bool {
	return imgui.InvisibleButton(str_id, size)
}
_ui_text :: proc(args: ..any) {
	imx.text(4096, ..args)
}
_ui_textf :: proc(format: string, args: ..any) {
	imx.textf(4096, format, ..args)
}
_ui_selectable :: proc(label: cstring, selected: bool) -> bool {
	return imgui.Selectable(label, selected)
}
_ui_toggleable :: proc(label: cstring, selected: ^bool) -> bool {
	return imgui.SelectableBoolPtr(label, selected)
}
_ui_button :: proc(label: cstring) -> bool {
	return imgui.Button(label)
}

_draw_many_rects :: proc(rects: []sdk.Rect, colors: []u32, thickness: f32, rounding: f32) {
	for r, index in rects {
		color := colors[index]
		imgui.DrawList_AddRect(ctx.drawlist, r.pmin, r.pmax, color, rounding, {}, thickness)
	}
}
_draw_rect :: proc(pmin, pmax: [2]f32, color: u32, thickness: f32, rounding: f32) {
	imgui.DrawList_AddRect(ctx.drawlist, pmin, pmax, color, rounding, {}, thickness)
}
_draw_many_rects_filled :: proc(rects: []sdk.Rect, colors: []u32, rounding: f32) {
	for r, index in rects {
		color := colors[index]
		imgui.DrawList_AddRectFilled(ctx.drawlist, r.pmin, r.pmax, color, rounding)
	}
}
_draw_rect_filled :: proc(pmin, pmax: [2]f32, color: u32, rounding: f32) {
	imgui.DrawList_AddRectFilled(ctx.drawlist, pmin, pmax, color, rounding)
}

_analysis_distribute_spectrum_frequencies :: proc(output: []f32) {
	analysis.calc_spectrum_frequencies(output)
}
_analysis_calc_spectrum :: proc(input: []f32, freq_cutoffs: []f32, output: []f32) {
	settings: Spectrum_Analyser_Settings
	settings.window_size = len(input)
	settings.output_size = auto_cast len(output)
	settings.freq_cutoff_hash = xxhash.XXH32(slice.to_bytes(freq_cutoffs))

	analyser := &ctx.spectrum_analysers[settings]
	if analyser == nil {

		log.debug("New spectrum analyser:", settings)

		ctx.spectrum_analysers[settings] = {}
		analyser = &ctx.spectrum_analysers[settings]
		analysis.spectrum_analyser_init(&analyser.state, settings.window_size, 1)
		analyser.output = make([]f32, len(output))
		analyser.calculated = false
	}

	if !analyser.calculated {
		for &f in analyser.output {f = 0}
		analysis.spectrum_analyser_calc(
			&analyser.state, input, freq_cutoffs,
			analyser.output, f32(ctx.cl.analysis.samplerate),
		)
		analyser.calculated = true
	}

	copy(output, analyser.output)
}

_playback_is_paused :: proc() -> bool {
	return server.is_paused(ctx.sv^)
}
_playback_set_paused :: proc(paused: bool) {
	server.set_paused(ctx.sv, paused)
}
_playback_toggle_paused :: proc() {
	server.set_paused(ctx.sv, !server.is_paused(ctx.sv^))
}
_playback_get_track_duration_seconds :: proc() -> int {
	return server.get_track_duration_seconds(ctx.sv)
}
_playback_seek_to_second :: proc(second: int) {
	server.seek_to_second(ctx.sv, second)
}

_library_lookup_track :: proc(id: sdk.Track_ID) -> (index: int, found: bool) {
	return server.library_lookup_track(ctx.sv.library, auto_cast id)
}

_library_get_track_metadata :: proc(index: int, out: ^sdk.Track_Metadata) {
	assert(index < len(ctx.sv.library.track_metadata))
	md := ctx.sv.library.track_metadata[index]
	out.artist = md.values[.Artist].(string) or_else ""
	out.album = md.values[.Album].(string) or_else ""
	out.title = md.values[.Title].(string) or_else ""
	out.genre = md.values[.Genre].(string) or_else ""
	out.duration_seconds = md.values[.Duration].(i64) or_else 0
	out.unix_added_date = md.values[.DateAdded].(i64) or_else 0
	out.unix_file_date = md.values[.FileDate].(i64) or_else 0
}

@private
sdk_init :: proc(cl: ^client.Client, sv: ^server.Server) {
	ctx.cl = cl
	ctx.sv = sv

	lib := &sdk_library_procs
	sdk_procs.library = lib
	lib.lookup_track = _library_lookup_track
	lib.get_track_metadata = _library_get_track_metadata

	draw := &sdk_draw_procs
	sdk_procs.draw = draw
	draw.rect = _draw_rect
	draw.many_rects = _draw_many_rects
	draw.rect_filled = _draw_rect_filled
	draw.many_rects_filled = _draw_many_rects_filled
	
	ui := &sdk_ui_procs
	sdk_procs.ui = ui
	ui.get_cursor = _ui_get_cursor
	ui.begin = _ui_begin
	ui.end = _ui_end
	ui.dummy = _ui_dummy
	ui.invisible_button = _ui_invisible_button
	ui.text = _ui_text
	ui.textf = _ui_textf
	ui.text_unformatted = imx.text_unformatted
	ui.selectable = _ui_selectable
	ui.toggleable = _ui_toggleable
	ui.button = _ui_button
	
	helpers := &sdk_helper_procs
	sdk_procs.helpers = helpers
	helpers.distribute_spectrum_frequencies = _analysis_distribute_spectrum_frequencies
	helpers.calc_spectrum = _analysis_calc_spectrum
	
	playback := &sdk_playback_procs
	sdk_procs.playback = playback
	playback.get_playing_track_id = _get_playing_track_id
	playback.is_paused = _playback_is_paused
	playback.set_paused = _playback_set_paused
	playback.toggle_paused = _playback_toggle_paused
	playback.get_track_duration_seconds = _playback_get_track_duration_seconds
	playback.seek_to_second = _playback_seek_to_second
}

@private
sdk_frame :: proc() {
	for settings, &a in ctx.spectrum_analysers {
		a.calculated = false
	}
}
