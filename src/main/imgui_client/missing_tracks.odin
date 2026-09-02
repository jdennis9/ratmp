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

import "core:os"
import "core:mem"
import "core:strings"
import "src:imx"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

missing_tracks_window_proc :: proc(ev: UI_Window_Event) -> bool {
	if ev.type != .Show {return false}

	_Row :: struct {
		track_id:       lib.Track_ID,
		path:           string,
		new_path:       string,
		selected:       bool,
		new_path_valid: bool,
	}

	@static w: struct {
		initialized:       bool,
		row_arena:         mem.Dynamic_Arena,
		rows:              [dynamic]_Row,
		serial:            uint,
		replace_target:    [512]u8,
		replace_str:       [512]u8,
		need_update:       bool,
		dont_check_paths:  bool,
	}

	_get_selection :: proc(allocator: mem.Allocator) -> []lib.Track_ID {
		res := make([]lib.Track_ID, len(w.rows), allocator)
		count := 0

		for row in w.rows {
			if row.selected {
				res[count] = row.track_id
				count += 1
			}
		}

		return res[:count]
	}

	_get_all_tracks :: proc(allocator: mem.Allocator) -> []lib.Track_ID {
		res := make([]lib.Track_ID, len(w.rows), allocator)

		for row, i in w.rows {
			res[i] = row.track_id
		}

		return res[:]
	}

	temp_allocator := get_frame_allocator()
	frame_allocator_guard()

	if w.need_update || w.serial != lib.get_missing_tracks_serial() {
		w.need_update = false
		w.serial = lib.get_missing_tracks_serial()
		tracks := lib.get_missing_tracks()

		if !w.initialized {
			w.initialized = true
			mem.dynamic_arena_init(&w.row_arena)
		}

		mem.dynamic_arena_free_all(&w.row_arena)
		row_allocator := mem.dynamic_arena_allocator(&w.row_arena)

		clear(&w.rows)

		old_cstr := cstring(&w.replace_target[0])
		new_cstr := cstring(&w.replace_str[0])

		for track_id in tracks {
			track := lib.get_track(track_id) or_continue

			track_path := strings.trim_prefix(track.url, "file://")
			replaced_path, _ := strings.replace_all(
				track_path,
				string(old_cstr),
				string(new_cstr),
				row_allocator
			)

			row := _Row {
				track_id       = track_id,
				path           = track_path,
				selected       = true,
				new_path       = replaced_path,
				new_path_valid = w.dont_check_paths ? false : os.exists(replaced_path),
			}

			append(&w.rows, row)
		}
	}

	// Find/replace here
	w.need_update |= imgui.InputText("Replace", cstring(&w.replace_target[0]), len(w.replace_target))
	w.need_update |= imgui.InputText("With", cstring(&w.replace_str[0]), len(w.replace_str))

	if imgui.Button("Apply") {
		ev := lib.Replace_Metadata_Event {
			tracks = _get_selection(temp_allocator),
			targets = {.URL},
			replace = string(cstring(&w.replace_target[0])),
			with    = string(cstring(&w.replace_str[0])),
		}

		lib.send_event(ev)
		w.need_update = true
	}

	imgui.Separator()

	if imgui.Button("Refresh") {
		lib.start_missing_tracks_scan()
	}

	imgui.SameLine()
	{
		check_exists := !w.dont_check_paths
		if imgui.Checkbox("Check paths", &check_exists) {
			w.dont_check_paths = !check_exists
		}
	}

	imgui.SetItemTooltip("Scan for missing tracks in the background (may take a minute)")

	table_flags := imgui.TableFlags_ScrollY|imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner|
		imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp

	imgui.BeginTable("Missing Tracks", 2, table_flags) or_return
	defer imgui.EndTable()

	imgui.TableSetupColumn("Current")
	imgui.TableSetupColumn("Change Preview")

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	for &row, row_index in w.rows {
		imgui.TableNextRow()

		path_cstring := strings.clone_to_cstring(row.path, temp_allocator)

		if !w.dont_check_paths {
			if row.new_path_valid {
				imgui.TableSetBgColor(.RowBg0, 0x5500ff00)
			}
			else {
				imgui.TableSetBgColor(.RowBg0, 0x550000ff)
			}
		}

		if imgui.TableSetColumnIndex(0) {
			if imgui.Selectable(path_cstring, row.selected, {.SpanAllColumns}) {
				select_table_rows(w.rows[:], row_index, false)
			}
		}

		if imgui.TableSetColumnIndex(1) {
			imx.text_unformatted(row.new_path)
		}
	}

	return true
}
