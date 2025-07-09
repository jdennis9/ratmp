#+private
package client

import "core:fmt"
import "core:hash/xxhash"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

import "imx"

_Playlist_Row :: struct {
	id: Playlist_ID,
	serial: uint,
	name: cstring,
	//duration: struct {h, m, s: u8},
	length: i32,
	duration_str: [9]u8,
	duration_len: int,
}

_Playlist_Table_2 :: struct {
	rows: [dynamic]_Playlist_Row,
	filter_hash: u32,
	serial: uint,
	viewing: Playlist_ID,
	playing: Playlist_ID,
	editing: Playlist_ID,
}

_Playlist_Table_Result :: struct {
	play: Maybe(Playlist_ID),
	select: Maybe(Playlist_ID),
	sort_spec: Maybe(server.Playlist_Sort_Spec),
	drag_drop_to: Maybe(Playlist_ID),
	context_menu: Maybe(Playlist_ID),
}

_update_playlist_table :: proc(
	table: ^_Playlist_Table_2, list: ^server.Playlist_List,
	filter: string, viewing: Playlist_ID, playing: Playlist_ID, editing: Playlist_ID,
) {
	filter_hash := xxhash.XXH32(transmute([]u8) string(filter))
	table.viewing = viewing
	table.playing = playing
	table.editing = editing
	
	if list.serial == table.serial && table.filter_hash == filter_hash && len(table.rows) != 0 {return}
	
	table.serial = list.serial
	table.filter_hash = filter_hash

	playlist_to_row :: proc(playlist: Playlist) -> _Playlist_Row {
		// @FixMe: If hours is more than 24, it comes up as 0
		h, m, s := util.clock_from_seconds(auto_cast playlist.duration)
		
		row := _Playlist_Row {
			id = playlist.id,
			serial = playlist.serial,
			name = playlist.name,
			length = auto_cast len(playlist.tracks),
		}

		row.duration_len = len(fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", h, m, s))

		return row
	}

	if filter != "" {
		filtered_playlist_ids: [dynamic]Playlist_ID
		defer delete(filtered_playlist_ids)

		clear(&table.rows)

		server.filter_playlists(list, filter, &filtered_playlist_ids)

		for id in filtered_playlist_ids {
			playlist := server.playlist_list_get(list^, id) or_continue
			row := playlist_to_row(playlist^)
			append(&table.rows, row)
		}
	}
	else {
		clear(&table.rows)
		for playlist in list.lists {
			append(&table.rows, playlist_to_row(playlist))
		}
	}
}

_display_playlist_table :: proc(
	theme: Theme, table: _Playlist_Table_2, str_id: cstring, context_menu_id: imgui.ID
) -> (result: _Playlist_Table_Result) {
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

			// @TODO: Find more clear way of showing this
			if row.id == table.editing {
				imgui.TableSetBgColor(.RowBg1, imgui.GetColorU32(.NavHighlight))
			}

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
					result.select = row.id
				}
				if row.name == nil {imgui.PopStyleColor()}

				if _play_track_input_pressed() {
					result.play = row.id
				}

				if imgui.IsItemClicked(.Right) {
					imgui.OpenPopupID(context_menu_id)
					result.context_menu = row.id
				}
			}
		}
	}

	return
}
