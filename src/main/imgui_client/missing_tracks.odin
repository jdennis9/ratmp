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

import "core:strings"
import "src:imx"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

missing_tracks_window_proc :: proc(ev: UI_Window_Event) -> bool {
	if ev.type != .Show {return false}

	_Row :: struct {
		track_id: lib.Track_ID,
		path:     string,
		selected: bool,
	}

	@static w: struct {
		rows:   [dynamic]_Row,
		serial: uint,
	}

	if w.serial != lib.get_missing_tracks_serial() {
		w.serial = lib.get_missing_tracks_serial()
		tracks := lib.get_missing_tracks()

		clear(&w.rows)

		for track_id in tracks {
			track := lib.get_track(track_id) or_continue

			row := _Row {
				track_id = track_id,
				path     = strings.trim_prefix(track.url, "file://"),
			}

			append(&w.rows, row)
		}
	}

	// Find/replace here

	if imgui.Button("Refresh") {
		lib.start_missing_tracks_scan()
	}

	imgui.SetItemTooltip("Scan for missing tracks in the background (may take a minute)")

	table_flags := imgui.TableFlags_ScrollY|imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner|
		imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp

	imgui.BeginTable("Missing Tracks", 1, table_flags) or_return
	defer imgui.EndTable()

	for &row in w.rows {
		if imgui.TableSetColumnIndex(0) {
			imx.text_unformatted(row.path)
		}
	}

	return true
}

