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
package client

import "core:time"
import "core:fmt"
import "src:imx"
import "src:main/shared"
import stbi "vendor:stb/image"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

metadata_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		cover_art:       Maybe(Texture_Handle),
		cover_art_w:     int,
		cover_art_h:     int,
		cover_art_ratio: f32,
		shown_track:     Maybe(lib.Track_ID),
	}

	playback_state := get_last_playback_state()
	temp_allocator := get_frame_allocator()

	release_cover_art :: proc() {
		if w.cover_art != nil {
			texture_release(w.cover_art.?)
			w.cover_art = nil
		}
	}

	update_track :: proc(track_id: lib.Track_ID) -> bool {
		w.shown_track = track_id

		cover_data := lib.find_track_cover_art(track_id, context.allocator) or_return
		defer delete(cover_data)

		tex, width, height := texture_create_from_memory(cover_data) or_return

		w.cover_art       = tex
		w.cover_art_w     = width
		w.cover_art_h     = height
		w.cover_art_ratio = f32(width) / f32(height)

		return true
	}

	if ev == .Hidden {
		release_cover_art()
		return false
	}

	if ev != .Show do return false

	if playback_state.track != w.shown_track {
		if playback_state.track == nil {
			release_cover_art()
			w.shown_track = nil
		}
		else {
			update_track(playback_state.track.?)
		}
	}

	if w.cover_art != nil {
		size := [2]f32{f32(w.cover_art_w), f32(w.cover_art_h)}
		scale := imgui.GetContentRegionAvail().x / f32(w.cover_art_w)

		imgui.PushStyleVarImVec2(.FramePadding, {})
		imgui.ImageButton("##art", texture_get_imgui_ref(w.cover_art.?) or_else {}, size * scale)
		imgui.PopStyleVar()
	}
	else {
		imgui.InvisibleButton("##art", imgui.GetContentRegionAvail().xx)
	}
	imgui.Separator()

	if w.shown_track != nil && imx.begin_kv_table("##metadata", imgui.TableFlags_RowBg) {
		defer imx.end_kv_table()

		track := lib.get_track(w.shown_track.?) or_return
		artists := lib.join_shared_strings(.Artist, track.artists, temp_allocator)
		genres := lib.join_shared_strings(.Genre, track.genres, temp_allocator)
		album := track.album != nil ? lib.get_shared_string(.Album, track.album.?) : ""

		h, m, s := time.clock_from_seconds(auto_cast track.duration)

		file_year, file_month, file_day := time.date(time.unix(track.file_date, 0))

		imx.kv_row("Title",  track.title)
		imx.kv_row("Artist", artists)
		imx.kv_row("Genres", genres)
		if album != "" do imx.kv_row("Album", album)
		imx.kv_rowf("Duration",           "%02d:%02d:%02d", h, m, s)
		imx.kv_rowf("File size",          "%M",             track.file_size)
		imx.kv_rowf("File creation time", "%d-%d-%d",       file_year, file_month, file_day)
	}

	return true
}
