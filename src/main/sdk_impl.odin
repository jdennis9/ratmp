/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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

import imgui "src:thirdparty/odin-imgui"

import "src:client"
import "src:server"
import "src:audio"
import "src:../sdk"

Spectrum_Analyser_Settings :: struct {
	window_size: int,
	output_size: u32,
	freq_cutoff_hash: u32,
}

ctx: struct {
	cl: ^client.Client,
	sv: ^server.Server,
	drawlist: ^imgui.DrawList,
}

@private sdk_procs: sdk.SDK
@private sdk_ui_procs: sdk.UI_Procs
@private sdk_draw_procs: sdk.Draw_Procs
@private sdk_analysis_procs: sdk.Analysis_Procs
@private sdk_playback_procs: sdk.Playback_Procs
@private sdk_library_procs: sdk.Library_Procs

_sdk_version :: proc() -> sdk.Version {
	return {0, 1, 0}
}
_get_playing_track_id :: proc() -> sdk.Track_ID {
	return auto_cast ctx.sv.current_track_id
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
	return server.library_find_track_index(ctx.sv.library, auto_cast id)
}

_library_get_track_metadata :: proc(index: int, out: ^sdk.Track_Metadata) {
	assert(index < len(ctx.sv.library.tracks))
	md := ctx.sv.library.tracks[index].properties
	out.artist = md[.Artist].(string) or_else ""
	out.album = md[.Album].(string) or_else ""
	out.title = md[.Title].(string) or_else ""
	out.genre = md[.Genre].(string) or_else ""
	out.duration_seconds = md[.Duration].(i64) or_else 0
	out.unix_added_date = md[.DateAdded].(i64) or_else 0
	out.unix_file_date = md[.FileDate].(i64) or_else 0
}

@private
sdk_init :: proc(cl: ^client.Client, sv: ^server.Server) {
	ctx.cl = cl
	ctx.sv = sv

	lib := &sdk_library_procs
	sdk_procs.library = lib
	lib.lookup_track = _library_lookup_track
	lib.get_track_metadata = _library_get_track_metadata
	
	sdk_ui_procs, sdk_draw_procs = client.get_sdk_impl()
	sdk_procs.ui = &sdk_ui_procs
	sdk_procs.draw = &sdk_draw_procs

	sdk_procs.analysis = &sdk_analysis_procs
	sdk_analysis_procs = audio.get_sdk_impl()
	
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

}
