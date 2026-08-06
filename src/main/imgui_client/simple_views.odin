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
import "src:main/shared"
import "src:imx"
import "src:main/player"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

library_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		track_table: Track_Table
	}

	if ev.type == .Free || ev.type == .Hidden {
		track_table_free(&w.track_table)
		return false
	}
	else if ev.type != .Show do return false

	tracks_serial := lib.get_tracks_serial()

	if !track_table_is_up_to_date(
		&w.track_table, tracks_serial, 0
	) {
		track_table_update(
			&w.track_table,
			tracks_serial,
			lib.get_all_track_ids(get_frame_allocator()),
			0
		)
	}

	track_table_show(&w.track_table, "##library", {})

	return true
}

queue_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		track_table: Track_Table
	}

	if ev.type == .Free || ev.type == .Hidden {
		track_table_free(&w.track_table)
		return false
	}
	else if ev.type != .Show do return false

	track_table_update(&w.track_table, player.get_queue_serial(), player.get_queue(), 1)
	events := track_table_show(&w.track_table, "##queue", {.IsQueue})

	if events.remove_selection {
		selection := track_table_get_selection(w.track_table, get_frame_allocator())
		player.remove_from_queue(selection)
	}

	if begin_window_drag_drop_target("##queue_drag_drop") {
		defer imgui.EndDragDropTarget()

		payload := get_track_drag_drop_payload(get_frame_allocator())
		if payload != nil {
			player.add_to_queue(payload, 0)
		}
	}

	return true
}

OPUS_OWNAGE :: `
2001-2023 Xiph.Org, Skype Limited, Octasic,
Jean-Marc Valin, Timothy B. Terriberry,
CSIRO, Gregory Maxwell, Mark Borgerding,
Erik de Castro Lopo, Mozilla, Amazon
`

license_window_proc :: proc(ev: UI_Window_Event) -> bool {
	if ev.type != .Show do return false

	_License :: struct {
		name:  cstring,
		owner: cstring,
		url:   cstring,
	}



	imx.text(128, "RAT MP", shared.PROGRAM_VERSION_STRING)
	imx.text_unformatted(shared.PROGRAM_LICENSE)

	@static licenses := [?]_License {
		{
			name  = "FFmpeg",
			owner = "2001 Fabrice Bellard",
			url   = "https://ffmpeg.org/",
		},
		{
			name  = "FreeType",
			owner = "1996-2002, 2006 by\nDavid Turner, Robert Wilhelm, and Werner Lemberg",
			url   = "https://freetype.org/",
		},
		{
			name  = "ImGui",
			owner = "2014-2026 Omar Cornut",
			url   = "https://github.com/ocornut/imgui",
		},
		{
			name  = "TagLib",
			owner = "2002-2008 by Scott Wheeler",
			url   = "https://taglib.org/",
		},
		{
			name  = "Opus",
			owner = OPUS_OWNAGE,
			url   = "https://opus-codec.org/",
		},
	}

	for l in licenses {
		imgui.Separator()
		imx.text_unformatted(string(l.name))
		imx.text_unformatted(string(l.owner))
		imgui.TextLinkOpenURL(l.url)
	}

	return true
}

about_window_proc :: proc(ev: UI_Window_Event) -> bool {
	if ev.type != .Show do return false
	
	imx.title_text(shared.PROGRAM_NAME)
	imx.text_unformatted("Version: " + shared.PROGRAM_VERSION_STRING)
	imx.text_unformatted("Odin compiler version: " + ODIN_VERSION)
	imx.text_unformatted("Odin compiler vendor: " + ODIN_VENDOR)
	
	{
		ts := time.unix(0, i64(ODIN_COMPILE_TIMESTAMP))
		y, m, d := time.date(ts)
		imx.textf(128, "Compile date: %d/%d/%d", y, m, d)
	}

	imx.text(64, "Optimization:", ODIN_OPTIMIZATION_MODE)
	imx.text(64, "Target architecture:", ODIN_ARCH)
	imx.text(64, "Target OS:", ODIN_OS_STRING)

	return true
}
