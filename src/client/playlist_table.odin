#+private
package client

import "core:time"
import "core:fmt"

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
	table.playlist = server.playlist_list_get(table.playlist_list, table.playlist_ids[table.index]) or_return

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
