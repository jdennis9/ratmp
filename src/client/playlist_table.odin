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
#+private
package client

import "core:mem"
import "core:strings"
import "core:time"
import "core:fmt"
import "core:hash/xxhash"

import imgui "src:thirdparty/odin-imgui"

import "src:server"

import "imx"

Playlist_Table_Row :: struct {
	name: cstring,
	id: Playlist_ID,
	duration: [9]u8,
	length: [6]u8,
	duration_len: u8,
	length_len: u8,
	is_auto_playlist: bool,
}

Playlist_Table :: struct {
	rows: [dynamic]Playlist_Table_Row,
	serial: uint,
	filter_hash: u32,
}

Playlist_Table_Result :: struct {
	select: Maybe(Playlist_ID),
	play: Maybe(Playlist_ID),
	append_to_queue: Maybe(Playlist_ID),
	drag_drop_to: Maybe(Playlist_ID),
	context_menu_target: Maybe(Playlist_ID),
	remove: Maybe(Playlist_ID),
	sort_spec: Maybe(server.Playlist_Sort_Spec),
}

playlist_table_update :: proc(
	table: ^Playlist_Table,
	playlists: []Playlist, serial: uint,
	filter: string,
) {
	playlist_to_row :: proc(playlist: Playlist) -> (row: Playlist_Table_Row) {
		row.name = playlist.name_cstring

		length_str := fmt.bprint(row.length[:], len(playlist.tracks))
		row.length_len = auto_cast len(length_str)

		hours, minutes, seconds := time.clock_from_seconds(auto_cast playlist.duration)
		row.duration_len = auto_cast len(fmt.bprintf(row.duration[:], "%02d:%02d:%02d", hours, minutes, seconds))

		row.id = playlist.id
		row.is_auto_playlist = playlist.auto_build_params != nil

		return
	}

	filter_hash := xxhash.XXH32(transmute([]u8) filter)

	if table.serial == serial && table.filter_hash == filter_hash {
		return
	}

	clear(&table.rows)

	if filter == "" {
		resize(&table.rows, len(playlists))

		for playlist, i in playlists {
			table.rows[i] = playlist_to_row(playlist)
		}
	}
	else {
		stack: mem.Stack
		stack_data := make([]byte, 4<<10)
		defer delete(stack_data)

		mem.stack_init(&stack, stack_data)
		allocator := mem.stack_allocator(&stack)

		filter_lower := strings.to_lower(filter, allocator)

		for playlist in playlists {
			name_lower := strings.to_lower(playlist.name, allocator)
			defer mem.stack_free(&stack, raw_data(name_lower))

			if strings.contains(name_lower, filter_lower) {
				append(&table.rows, playlist_to_row(playlist))
			}
		}
	}
}

playlist_table_free :: proc(table: ^Playlist_Table) {
	delete(table.rows)
	table.rows = nil
	table.serial = 0
	table.filter_hash = 0
}

playlist_table_show :: proc(table: Playlist_Table, lib: Library, viewing_id: Playlist_ID, editing_id: Playlist_ID, playing_id: Global_Playlist_ID) -> (result: Playlist_Table_Result, shown: bool) {
	table_flags := imgui.TableFlags_Sortable |
		imgui.TableFlags_SortTristate |
		imgui.TableFlags_SizingStretchProp |
		imgui.TableFlags_ScrollY |
		imgui.TableFlags_RowBg |
		imgui.TableFlags_Resizable |
		imgui.TableFlags_BordersInner |
		imgui.TableFlags_Hideable |
		imgui.TableFlags_Reorderable

	imgui.BeginTable("##playlists", 3, table_flags) or_return
	defer imgui.EndTable()
	shown = true

	imgui.TableSetupColumn("Name")
	imgui.TableSetupColumn("No. Tracks")
	imgui.TableSetupColumn("Duration")

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	if table_sort_specs := imgui.TableGetSortSpecs(); table_sort_specs != nil {
		if specs := table_sort_specs.Specs; specs != nil && table_sort_specs.SpecsDirty {
			metric: server.Playlist_Sort_Metric
			order: server.Sort_Order

			table_sort_specs.SpecsDirty = false

			switch specs.ColumnIndex {
				case 0: metric = .Name
				case 1: metric = .Length
				case 2: metric = .Duration
			}

			switch specs.SortDirection {
				case .Ascending: order = .Ascending
				case .Descending: order = .Descending
				case .None: order = .Descending
			}

			result.sort_spec = server.Playlist_Sort_Spec {
				metric = metric,
				order = order,
			}
		}
	}

	for &row in table.rows {
		imgui.TableNextRow()
		imgui.PushIDPtr(&row)
		defer imgui.PopID()

		if playing_id.origin == .User && row.id == cast(Playlist_ID)playing_id.id {
			imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(global_theme.custom_colors[.PlayingHighlight]))
		}

		if imgui.TableSetColumnIndex(0) {
			if imgui.Selectable(row.name, viewing_id == row.id, {.SpanAllColumns}) {
				result.select = row.id
			}

			if imgui.BeginDragDropSource() {
				if playlist, _, found_playlist := server.library_get_playlist(lib, row.id); found_playlist {
					set_track_drag_drop_payload(playlist.tracks[:])
				}
				imgui.EndDragDropSource()
			}

			if is_play_track_input_pressed() {
				result.play = row.id
				result.select = row.id
			}

			if imgui.BeginPopupContextItem() {
				if imgui.MenuItem("Play") {
					result.play = row.id
					result.select = row.id
				}
				if imgui.MenuItem("Append to queue") {
					result.append_to_queue = row.id
				}
				imgui.Separator()
				if imgui.MenuItem("Remove") {
					result.remove = row.id
				}
				imgui.EndPopup()
			}

			if row.is_auto_playlist {
				imgui.SameLine()
				imgui.TextDisabled("[Auto]")
			}
		}

		if imgui.TableSetColumnIndex(1) {
			imx.text_unformatted(string(row.length[:row.length_len]))
		}

		if imgui.TableSetColumnIndex(2) {
			imx.text_unformatted(string(row.duration[:row.duration_len]))
		}
	}

	return
}
