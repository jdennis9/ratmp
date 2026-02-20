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
import "base:runtime"
import "core:time"
import "core:fmt"
import "core:hash/xxhash"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

import "imx"

Track_Row :: struct {
	genre, artist, album: string,
	genre_width, artist_width, album_width: f32,
	title: cstring,
	duration_str: [9]u8,
	duration_len: int,
	year_str: [4]u8,
	id: Track_ID,
	track_num, bitrate: i32,
	// @NOTE: Increase this to 5 characters in the 11th millenium
	date_added_str: [10]u8,
	file_date_str: [10]u8,
	selected: bool,
}

Track_Table :: struct {
	serial: uint,
	columns: [len(Track_Property_ID)]imx.Table_Column_Info,
	rows: []imx.Table_Row,
	selection: []Track_ID,
	arena: mem.Dynamic_Arena,
	initialized: bool,
	playlist_id: Global_Playlist_ID,
	filter_hash: u32,
	filter: [256]u8,
}

Track_Table_Show_Flag :: enum {
	IsQueue,
	NoEditMetadata,
	NoPlay,
	NoFilter,
}

Track_Table_Info :: struct {
	str_id: cstring,
	tracks: []Track_ID,
	tracks_serial: uint,
	playlist_id: Global_Playlist_ID,
	flags: bit_set[Track_Table_Show_Flag],
	context_id: Maybe(imgui.ID),
	
	callback_data: rawptr,
	sort_callback: proc(data: rawptr, spec: server.Track_Sort_Spec),
	remove_callback: proc(data: rawptr, tracks: []Track_ID),
}

track_table_get_tracks :: proc(table: Track_Table) -> []Track_ID {
	ids := make([]Track_ID, len(table.rows))
	for row, i in table.rows {
		ids[i] = auto_cast row.id
	}

	return ids
}

track_table_get_selection :: proc(table: Track_Table) -> []Track_ID {
	return table.selection
}

track_table_free :: proc(table: ^Track_Table) {
	mem.dynamic_arena_free_all(&table.arena)
	table.serial = 0
}

track_table_accept_drag_drop :: proc(str_id: cstring, bb: imgui.Rect, allocator: runtime.Allocator) -> (payload: []Track_ID, have_payload: bool) {
	imgui.BeginDragDropTargetCustom(bb, imgui.GetID(str_id)) or_return
	defer imgui.EndDragDropTarget()

	return get_track_drag_drop_payload(allocator)
}


show_track_table :: proc(table: ^Track_Table, cl: ^Client, sv: ^Server, info: Track_Table_Info) -> bool {
	assert(info.str_id != nil)

	if !table.initialized {
		mem.dynamic_arena_init(&table.arena)
		table.initialized = true
	}

	_update_table :: proc(table: ^Track_Table, info: Track_Table_Info, filter: string, filter_hash: u32, lib: Library) {
		util.SCOPED_TIMER("Update track table")
		table.serial = info.tracks_serial
		table.playlist_id = info.playlist_id
		table.filter_hash = filter_hash

		mem.dynamic_arena_free_all(&table.arena)
		allocator := mem.dynamic_arena_allocator(&table.arena)

		tracks: [dynamic]Track_ID

		server.filter_tracks(lib, {
			components = ~{},
			filter = filter,
		}, info.tracks, &tracks)
		defer delete(tracks)

		visible_track_count := len(tracks)

		table.rows = make([]imx.Table_Row, visible_track_count, allocator)
		for track_id, i in tracks {
			table.rows[i].id = auto_cast track_id
		}

		column_names := [Track_Property_ID]cstring {
			.Album = "Album",
			.Genre = "Genre",
			.Artist = "Artist",
			.Title = "Title",
			.TrackNumber = "Track",
			.Duration = "Duration",
			.Bitrate = "Bitrate",
			.Year = "Year",
			.DateAdded = "Date Added",
			.FileDate = "File Date",
		}

		default_shown_props := bit_set[Track_Property_ID] {
			.Album, .Artist, .Title, .Duration
		}

		for prop in Track_Property_ID {
			col := &table.columns[prop]
			col.rows = make([]imx.Table_Row_Content, len(tracks), allocator)
			col.name = column_names[prop]
			if prop not_in default_shown_props do col.flags |= {.DefaultHide}
		}

		for track_id, row_index in tracks {
			track := server.library_find_track(lib, track_id) or_continue
			
			for prop in Track_Property_ID {
				rows := table.columns[prop].rows
				row := &rows[row_index]

				switch prop {
					case .Album, .Genre, .Title, .Artist:
						row.text = track.properties[prop].(string) or_else ""
					case .DateAdded, .FileDate:
						ts := time.unix(track.properties[prop].(i64) or_break, 0)
						y, m, d := time.year(ts), time.month(ts), time.day(ts)
						row.text = fmt.aprintf("%02d-%02d-%02d", y, m, d)
					case .TrackNumber, .Year:
						row.text = fmt.aprint(track.properties[prop].(i64) or_else 0)
					case .Bitrate:
						row.text = fmt.aprint(track.properties[prop].(i64), "kb/s")
					case .Duration:
						h, m, s := time.clock_from_seconds(auto_cast (track.properties[.Duration].(i64) or_else 0))
						row.text = fmt.aprintf("%02d:%02d:%02d", h, m, s, allocator = allocator)
				}

				row.text_width = imx.calc_text_size(row.text).x
			}
		}
	}

	filter_cstring := cstring(&table.filter[0])

	if .NoFilter not_in info.flags {
		imgui.InputTextWithHint("##filter", "Filter", filter_cstring, auto_cast len(table.filter))
	}

	// Check if the table needs to update
	if filter_hash := xxhash.XXH32(
		transmute([]u8) string(filter_cstring),
	); info.tracks_serial != table.serial ||
		info.playlist_id != table.playlist_id ||
		filter_hash != table.filter_hash {
		_update_table(table, info, string(filter_cstring), filter_hash, sv.library)
	}

	// Show table
	context_id := info.context_id.? or_else imgui.GetID("##track_context")
	r := imx.table_show(info.str_id, imx.Table_Display_Info {
		columns = table.columns[:],
		rows = table.rows,
		highlight_color = imgui.GetColorU32ImVec4(global_theme.custom_colors[.PlayingHighlight]),
		highlight_row_id = auto_cast sv.current_track_id,
		context_menu_id = context_id,
		drag_drop_payload_type = "TRACKS",
	}) or_return

	actions: struct {
		play_track_id: Maybe(Track_ID),
		context_menu_target: Maybe(Track_ID),
		go_to_artist, go_to_album, go_to_genre: bool,
		start_radio: bool,
		play_selection: bool,
		remove_selection: bool,
		queue_selection: bool,
		add_selection_to_playlist: Maybe(Playlist_ID),
		edit_metadata: bool,
		more_info: bool,
	}

	Column_Info :: struct {
		property: Track_Property_ID,
		default_show: bool,
	}
	
	// Process result
	if r.selection_changed {
		ids: [dynamic]Track_ID

		for row in table.rows {
			if row.selected {
				append(&ids, cast(Track_ID) row.id)
			}
		}

		table.selection = ids[:]
	}

	if r.middle_clicked_row != nil do actions.play_track_id = cast(Track_ID) r.middle_clicked_row.?
	if r.context_menu_opened_with != nil {
		actions.context_menu_target = cast(Track_ID) r.context_menu_opened_with.?
	}

	// Sort
	if r.sort_by_column != nil && info.sort_callback != nil {
		order: server.Sort_Order
		property_id := cast(Track_Property_ID) r.sort_by_column.?

		switch r.sort_order {
			case .None, .Ascending: order = .Ascending
			case .Descending: order = .Descending
		}

		info.sort_callback(info.callback_data, server.Track_Sort_Spec {
			metric = property_id,
			order = order,
		})
	}

	// Context menu
	if imgui.BeginPopupEx(context_id, {.AlwaysAutoResize} | imgui.WindowFlags_NoDecoration) {
		assert(r.context_menu_opened_with != nil)

		if .NoPlay not_in info.flags && imgui.MenuItem("Play selected tracks") {
			actions.play_selection = true
		}

		if imgui.BeginMenu("Add to playlist") {
			for playlist in sv.library.playlists {
				if playlist.auto_build_params != nil do continue
				global_id := Global_Playlist_ID {.User, auto_cast playlist.id}
				if global_id != table.playlist_id && imgui.MenuItem(playlist.name_cstring) {
					actions.add_selection_to_playlist = playlist.id
				}
			}
			imgui.EndMenu()
		}

		if .IsQueue not_in info.flags do actions.queue_selection |= imgui.MenuItem("Add to queue")

		actions.start_radio |= imgui.MenuItem("Play similar music")

		if imgui.BeginMenu("Go to") {
			actions.go_to_album |= imgui.MenuItem("Album")
			actions.go_to_artist |= imgui.MenuItem("Artist")
			actions.go_to_genre |= imgui.MenuItem("Genre")
			imgui.EndMenu()
		}

		if len(table.selection) == 1 {
			imgui.Separator()
			actions.more_info |= imgui.MenuItem("More info...")
		}

		if info.flags != {} do imgui.Separator()
		if .NoEditMetadata not_in info.flags do actions.edit_metadata |= imgui.MenuItem("Edit metadata")
		if info.remove_callback != nil do actions.remove_selection |= imgui.MenuItem("Remove")

		imgui.EndPopup()
	}

	// Process all input
	if .NoPlay not_in info.flags && actions.play_track_id != nil {
		tracks := track_table_get_tracks(table^)
		defer delete(tracks)

		if .IsQueue not_in info.flags {
			server.play_playlist(sv, tracks[:], table.playlist_id, actions.play_track_id.?)
		}
		else {
			server.set_queue_track(sv, actions.play_track_id.?)
		}
	}

	if .NoPlay not_in info.flags && actions.play_selection {
		server.play_playlist(sv, table.selection[:], table.playlist_id)
	}

	if actions.queue_selection {
		server.append_to_queue(sv, table.selection[:], table.playlist_id)
	}

	if actions.remove_selection && info.remove_callback != nil {
		info.remove_callback(info.callback_data, table.selection[:])
	}

	if actions.edit_metadata {
		window := bring_window_to_front(cl, WINDOW_METADATA_EDITOR) or_else nil
		if window != nil {
			metadata_editor_window_select_tracks(auto_cast window, table.selection[:])
		}
	}

	if actions.more_info {
		assert(actions.context_menu_target != nil)
		window := bring_window_to_front(cl, WINDOW_METADATA_POPUP) or_else nil
		if window != nil {
			s := cast(^Metadata_Window) window
			s.track_id = actions.context_menu_target.?
		}
	}

	if actions.add_selection_to_playlist != nil {
		playlist, _, found := server.library_get_playlist(sv.library, actions.add_selection_to_playlist.?)
		if found do server.playlist_add_tracks(playlist, &sv.library, table.selection[:])
	}

	if actions.start_radio {
		if track_index, found := server.library_find_track_index(
			sv.library, actions.context_menu_target.?
		); found {
			radio := server.library_build_track_radio(sv.library, track_index, context.allocator)
			defer delete(radio)
			server.play_playlist(sv, radio[:], {.Generated, 0}, actions.context_menu_target.?)
		}
	}

	if actions.go_to_album {
		track, found := server.library_find_track(sv.library, actions.context_menu_target.?)
		if found do go_to_album(cl, track.properties)
	}

	if actions.go_to_artist {
		track, found := server.library_find_track(sv.library, actions.context_menu_target.?)
		if found do go_to_artist(cl, track.properties)
	}

	if actions.go_to_genre {
		track, found := server.library_find_track(sv.library, actions.context_menu_target.?)
		if found do go_to_genre(cl, track.properties)
	}

	return true
}

show_track_table_test :: proc(cl: ^Client, sv: ^Server) -> bool {
	@static flags: bit_set[Track_Table_Show_Flag]
	@static table: Track_Table

	defer imgui.End()
	imgui.Begin("Track Table Test") or_return

	for flag in Track_Table_Show_Flag {
		name: [32]u8
		fmt.bprint(name[:31], flag)
		selected := flag in flags

		if imgui.Checkbox(cstring(&name[0]), &selected) {
			if selected do flags |= {flag}
			else do flags ~= {flag}
		}
	}

	show_track_table(&table, cl, sv, Track_Table_Info {
		flags = flags,
		str_id = "##track_table_test",
		tracks = server.library_get_all_track_ids(sv.library),
		tracks_serial = sv.library.serial,
		playlist_id = {.Loose, 0},
	})

	return true
}
