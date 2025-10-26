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
#+private
package client

import "core:fmt"
import "core:hash/xxhash"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

import "imx"

/*Playlist_Row :: struct {
	id: Global_Playlist_ID,
	serial: uint,
	name: cstring,
	//duration: struct {h, m, s: u8},
	length: i32,
	duration_str: [9]u8,
	duration_len: int,
}

Playlist_Table :: struct {
	rows: [dynamic]Playlist_Row,
	filter_hash: u32,
	serial: uint,
	viewing: Global_Playlist_ID,
	playing: Global_Playlist_ID,
	editing: Global_Playlist_ID,
}

Playlist_Table_Result :: struct {
	play: Maybe(Local_Playlist_ID),
	select: Maybe(Local_Playlist_ID),
	sort_spec: Maybe(server.Playlist_Sort_Spec),
	drag_drop_to: Maybe(Local_Playlist_ID),
	context_menu: Maybe(Local_Playlist_ID),
}

playlist_table_update :: proc(
	table: ^Playlist_Table, list: ^server.Playlist_List,
	filter: string, viewing: Global_Playlist_ID, playing: Global_Playlist_ID, editing: Global_Playlist_ID,
) {
	filter_hash := xxhash.XXH32(transmute([]u8) string(filter))
	table.viewing = viewing
	table.playing = playing
	table.editing = editing
	
	if list.serial == table.serial && table.filter_hash == filter_hash && len(table.rows) != 0 {return}
	
	table.serial = list.serial
	table.filter_hash = filter_hash

	playlist_to_row :: proc(playlist: server.Playlist_Ptr) -> Playlist_Row {
		// @FixMe: If hours is more than 24, it comes up as 0
		h, m, s := util.clock_from_seconds(auto_cast playlist.duration)
		
		row := Playlist_Row {
			id = server.playlist_global_id(playlist),
			serial = playlist.serial,
			name = playlist.name_cstring,
			length = auto_cast len(playlist.tracks),
		}

		row.duration_len = len(fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", h, m, s))

		return row
	}

	if filter != "" {
		filtered_playlist_ids: [dynamic]Local_Playlist_ID
		defer delete(filtered_playlist_ids)

		clear(&table.rows)

		//server.filter_playlists(list, filter, &filtered_playlist_ids)
		server.playlist_list_filter_by_name(list^, filter, &filtered_playlist_ids)

		for id in filtered_playlist_ids {
			playlist, _ := server.playlist_list_find_playlist(list, id) or_continue
			row := playlist_to_row(playlist)
			append(&table.rows, row)
		}
	}
	else {
		clear(&table.rows)
		for _, index in list.playlists {
			append(&table.rows, playlist_to_row(&list.playlists[index]))
		}
	}
}

playlist_table_show :: proc(
	theme: Theme, table: Playlist_Table, str_id: cstring, context_menu_id: imgui.ID
) -> (result: Playlist_Table_Result) {
	list_clipper: imgui.ListClipper
	table_flags := 
		imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate|
		imgui.TableFlags_RowBg|imgui.TableFlags_ScrollY|imgui.TableFlags_Reorderable|
		imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp|imgui.TableFlags_BordersInner

	if len(table.rows) == 0 {return}

	if !imgui.BeginTable(str_id, 3, table_flags) {return}
	defer imgui.EndTable()

	imgui.TableSetupColumn("Name")
	imgui.TableSetupColumn("Length")
	imgui.TableSetupColumn("Duration")

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	table_sort_spec := imgui.TableGetSortSpecs()
	if table_sort_spec != nil && table_sort_spec.SpecsDirty && table_sort_spec.Specs != nil {
		table_spec := table_sort_spec.Specs
		sort_spec := server.Playlist_Sort_Spec{}

		switch table_spec.ColumnIndex {
			case 0: sort_spec.metric = .Name
			case 1: sort_spec.metric = .Length
			case 2: sort_spec.metric = .Duration
		}

		switch table_spec.SortDirection {
			case .Ascending: sort_spec.order = .Ascending
			case .Descending, .None: sort_spec.order = .Descending
		}

		result.sort_spec = sort_spec
		table_sort_spec.SpecsDirty = false
	}

	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows), imgui.GetTextLineHeightWithSpacing())
	defer imgui.ListClipper_End(&list_clipper)

	for imgui.ListClipper_Step(&list_clipper) {
		for index in list_clipper.DisplayStart..<list_clipper.DisplayEnd {
			row := table.rows[index]
			imgui.TableNextRow()

			if row.id == table.playing {
				imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(theme.custom_colors[.PlayingHighlight]))
			}

			if imgui.TableSetColumnIndex(2) {
				imx.text_unformatted(string(row.duration_str[:row.duration_len]))
			}

			if imgui.TableSetColumnIndex(1) {
				imgui.Text("%d", row.length)
			}

			if imgui.TableSetColumnIndex(0) {
				if row.name == nil {imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))}
				if imgui.Selectable(row.name != nil ? row.name : "None", table.viewing == row.id, {.SpanAllColumns}) {
					result.select = row.id.id
				}
				if row.name == nil {imgui.PopStyleColor()}

				if is_play_track_input_pressed() {
					result.play = row.id.id
				}

				if imgui.IsItemClicked(.Right) {
					imgui.OpenPopupID(context_menu_id)
					result.context_menu = row.id.id
				}
			}
		}
	}

	return
}

playlist_table_free :: proc(table: ^Playlist_Table) {
	delete(table.rows)
	table^ = {}
}*/
