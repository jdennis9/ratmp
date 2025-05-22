#+private
package client

import "core:time"
import "core:fmt"
import "core:hash/xxhash"

import imgui "src:thirdparty/odin-imgui"

import "src:server"

_Playlist_Table :: struct {
	playlist_list: ^server.Playlist_List,
	playlist_ids: []Playlist_ID,
	playlist: ^Playlist,
	selection: ^Playlist_ID,
	index: int,
	_pos, _min, _max: int,
	_list_clipper: ^imgui.ListClipper,
}

_begin_playlist_table :: proc(
	str_id: cstring,
	playlist_list: ^server.Playlist_List,
	playlist_ids: []Playlist_ID,
	selection: ^Playlist_ID,
) -> (table: _Playlist_Table, show: bool) {
	assert(selection != nil)

	table_flags := 
		imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate|
		imgui.TableFlags_RowBg|imgui.TableFlags_ScrollY|imgui.TableFlags_Reorderable|
		imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp

	if len(playlist_ids) == 0 {return}

	if imgui.BeginTable(str_id, 3, table_flags) {
		table.playlist_list = playlist_list
		table.playlist_ids = playlist_ids
		table.index = -1
		table.selection = selection

		imgui.TableSetupColumn("Name")
		imgui.TableSetupColumn("Length")
		imgui.TableSetupColumn("Duration")

		imgui.TableSetupScrollFreeze(1, 1)
		imgui.TableHeadersRow()

		table._list_clipper = new(imgui.ListClipper)
		imgui.ListClipper_Begin(table._list_clipper, auto_cast len(table.playlist_ids))
		show = true
		return
	}

	return
}

_playlist_table_update_sort_spec :: proc(out_spec: ^server.Playlist_Sort_Spec) -> bool {
	sort_spec := imgui.TableGetSortSpecs()
	if sort_spec == nil || !sort_spec.SpecsDirty {return false}
	sort_spec.SpecsDirty = false
	if sort_spec.Specs == nil {return false}

	column := sort_spec.Specs.ColumnIndex
	direction := sort_spec.Specs.SortDirection

	switch direction {
		case .Ascending, .None: out_spec.order = .Ascending
		case .Descending: out_spec.order = .Descending
	}

	switch column {
		case 0: out_spec.metric = .Name
		case 1: out_spec.metric = .Length
		case 2: out_spec.metric = .Duration
	}

	return true
}

_playlist_table_row :: proc(cl: ^Client, table: ^_Playlist_Table, sv: Server) -> (not_done: bool) {
	if table._pos >= table._max {
		if !imgui.ListClipper_Step(table._list_clipper) {
			return false
		}

		table._min = int(table._list_clipper.DisplayStart)
		table._max = int(table._list_clipper.DisplayEnd)
		table._pos = table._min
	}

	table.index = table._pos
	table._pos += 1
	if table.index >= len(table.playlist_ids) {return false}
	table.playlist = server.playlist_list_get(table.playlist_list^, table.playlist_ids[table.index]) or_return

	imgui.TableNextRow()

	if sv.current_playlist_id == table.playlist.id {
		imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(cl.theme.custom_colors[.PlayingHighlight]))
	}

	if imgui.TableSetColumnIndex(1) {
		imgui.Text("%u", u32(len(table.playlist.tracks)))
	}

	if imgui.TableSetColumnIndex(2) {
		buf: [12]u8
		h, m, s := time.clock_from_seconds(auto_cast table.playlist.duration)
		str := fmt.bprintf(buf[:11], "%02d:%02d:%02d", h, m, s)
		//imgui.Text("%02d:%02d:%02d", i32(h), i32(m), i32(s))
		_native_text_unformatted(str)
	}

	if imgui.TableSetColumnIndex(0) {
		not_done = true
		name_empty := table.playlist.name == ""

		if name_empty {imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))}
		defer if name_empty {imgui.PopStyleColor()}

		if imgui.Selectable(
			name_empty ? "None" : table.playlist.name,
			table.playlist.id == table.selection^, {.SpanAllColumns}
		) {
			table.selection^ = table.playlist.id
		}

		if imgui.BeginDragDropSource() {
			_set_track_drag_drop_payload(cl, table.playlist.tracks[:])
			imgui.EndDragDropSource()
		}
	}

	return
}

_end_playlist_table :: proc(table: ^_Playlist_Table) {
	imgui.ListClipper_End(table._list_clipper)
	free(table._list_clipper)
	imgui.EndTable()
}

import "core:log"

_Playlist_Row :: struct {
	id: Playlist_ID,
	serial: uint,
	name: cstring,
	//duration: struct {h, m, s: u8},
	duration_str: [8]u8,
	length: i32,
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
		h, m, s := time.clock_from_seconds(auto_cast playlist.duration)
		
		row := _Playlist_Row {
			id = playlist.id,
			serial = playlist.serial,
			name = playlist.name,
			length = auto_cast len(playlist.tracks),
		}

		fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", h, m, s)

		return row
	}

	if filter != "" {
		filtered_playlist_ids: [dynamic]Playlist_ID
		defer delete(filtered_playlist_ids)

		clear(&table.rows)

		server.filter_playlists(list, filter, &filtered_playlist_ids)

		for id in filtered_playlist_ids {
			playlist := server.playlist_list_get(list^, id) or_continue
			h, m, s := time.clock_from_seconds(auto_cast playlist.duration)
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
				_native_text_unformatted(string(row.duration_str[:]))
			}

			if imgui.TableSetColumnIndex(1) {
				imgui.Text("%d", row.length)
			}

			if imgui.TableSetColumnIndex(0) {
				sel_flags := imgui.SelectableFlags{.SpanAllColumns}

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
