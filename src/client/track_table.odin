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

Track_Table_Flag :: enum {NoSort,}
Track_Table_Flags :: bit_set[Track_Table_Flag]

Track_Table_Result :: struct {
	play: Maybe(Track_ID),
	select: Maybe(Track_ID),
	context_menu_target: Maybe(Track_ID),
	selection_count: int,
	lowest_selection_index: int,
	sort_spec: Maybe(server.Track_Sort_Spec),
	play_selection: bool,
	add_selection_to_queue: bool,
	pick_up_drag_drop_payload: []Track_ID,
}

Track_Table_Result_Process_Flag :: enum {
	// Set queue position to track rather than replace queue with the tables tracks
	SetQueuePos,
}
Track_Table_Result_Process_Flags :: bit_set[Track_Table_Result_Process_Flag]

Track_Context_Flag :: enum {NoRemove, NoQueue, NoEditMetadata}
Track_Context_Flags :: bit_set[Track_Context_Flag]
Track_Context_Result :: struct {
	single_track: Maybe(Track_ID),
	add_to_playlist: Maybe(server.Playlist_ID),
	go_to_album: bool,
	go_to_artist: bool,
	go_to_genre: bool,
	remove: bool,
	play: bool,
	edit_metadata: bool,
	add_to_queue: bool,
	more_info: bool,
}

show_add_to_playlist_menu :: proc(lib: Library, result: ^Track_Context_Result) {
	if imgui.BeginMenu("Add to playlist") {
		for playlist in lib.playlists {
			if imgui.MenuItem(playlist.name_cstring) {
				result.add_to_playlist = playlist.id
			}
		}
		imgui.EndMenu()
	}
}

show_track_context_items :: proc(
	track_id: Track_ID,
	result: ^Track_Context_Result,
	lib: Library,
) {
	if imgui.BeginMenu("Go to") {
		if imgui.MenuItem("Album") {result.go_to_album = true}
		if imgui.MenuItem("Artist") {result.go_to_artist = true}
		if imgui.MenuItem("Genre") {result.go_to_genre = true}
		imgui.EndMenu()
	}
	show_add_to_playlist_menu(lib, result)
	imgui.Separator()
	if imgui.MenuItem("More info...") {
		result.more_info = true
	}
}

show_track_context :: proc(
	track_id: Track_ID,
	context_id: imgui.ID,
	lib: Library,
) -> (result: Track_Context_Result) {
	result.single_track = track_id
	if imgui.BeginPopupEx(context_id, {.AlwaysAutoResize} | imgui.WindowFlags_NoDecoration) {
		show_track_context_items(track_id, &result, lib)
		imgui.EndPopup()
	}
	return
}

process_track_context :: proc(
	track_id: Track_ID,
	result: Track_Context_Result,
	cl: ^Client,
	sv: ^Server,
	from_playlist: Global_Playlist_ID,
	allow_add_to_playlist: bool,
) {
	if result.single_track != nil {
		if (result.go_to_album || result.go_to_genre || result.go_to_artist) {
			track, found := server.library_find_track(sv.library, result.single_track.?)
			if found {
				if result.go_to_album {go_to_album(cl, track.properties)}
				if result.go_to_artist {go_to_artist(cl, track.properties)}
				if result.go_to_genre {go_to_genre(cl, track.properties)}
			}
		}

		if result.edit_metadata {
			if editor, ok := bring_window_to_front(cl, WINDOW_METADATA_EDITOR); ok {
				metadata_editor_window_select_tracks(auto_cast editor, {result.single_track.?})
			}
		}

		if result.play {
			server.play_playlist(sv, {result.single_track.?}, from_playlist)
		}

		if result.add_to_queue {
			server.append_to_queue(sv, {result.single_track.?}, from_playlist)
		}
	}

	if allow_add_to_playlist && result.add_to_playlist != nil {
		_, track_found := server.library_find_track(sv.library, track_id)
		playlist, _, playlist_found := server.library_get_playlist(sv.library, result.add_to_playlist.?)
		if track_found && playlist_found {
			server.playlist_add_tracks(playlist, &sv.library, {track_id})
		}
	}

	if result.more_info do open_track_in_metadata_popup(cl, track_id)
}

// -----------------------------------------------------------------------------
// Example usage of replacement table API
// -----------------------------------------------------------------------------

Track_Table :: struct {
	serial: uint,
	state: imx.Table_State,
	columns: [len(Track_Property_ID)]imx.Table_Column_Info,
	rows: []imx.Table_Row,
	arena: mem.Dynamic_Arena,
	uptime: f64,
	initialized: bool,
	playlist_id: Global_Playlist_ID,
	filter_hash: u32,
}

track_table_update :: proc(
	cl: Client,
	table: ^Track_Table,
	serial: uint,
	lib: server.Library,
	unfiltered_tracks: []Track_ID,
	playlist_id: Global_Playlist_ID,
	filter: string,
	flags: Track_Table_Flags = {},
) {
	table.uptime = cl.uptime

	if !table.initialized do mem.dynamic_arena_init(&table.arena)

	filter_hash := xxhash.XXH32(transmute([]u8) filter)

	if serial == table.serial && table.playlist_id == playlist_id && filter_hash == table.filter_hash do return

	util.SCOPED_TIMER("Update track table")

	table.serial = serial
	table.playlist_id = playlist_id
	table.filter_hash = filter_hash

	mem.dynamic_arena_free_all(&table.arena)
	allocator := mem.dynamic_arena_allocator(&table.arena)

	tracks: [dynamic]Track_ID
	server.filter_tracks(lib, {
		components = ~{},
		filter = filter
	}, unfiltered_tracks, &tracks)
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

track_table_show :: proc(
	table: Track_Table,
	str_id: cstring,
	context_menu_id: imgui.ID,
	playing: Track_ID,
) -> (result: Track_Table_Result) {
	columns := table.columns
	window_bb := imx.get_window_bounding_box()

	display := imx.Table_Display_Info {
		columns = columns[:],
		rows = table.rows,
		highlight_color = imgui.GetColorU32ImVec4(global_theme.custom_colors[.PlayingHighlight]),
		highlight_row_id = auto_cast playing,
		context_menu_id = context_menu_id,
		drag_drop_payload_type = "TRACKS",
	}

	r, _ := imx.table_show(str_id, display, table.uptime)

	if r.middle_clicked_row != nil do result.play = cast(Track_ID) r.middle_clicked_row.?
	if r.left_clicked_row != nil do result.select = cast(Track_ID) r.left_clicked_row.?
	if r.context_menu_opened_with != nil do result.context_menu_target = cast(Track_ID) r.context_menu_opened_with.?

	if r.sort_by_column != nil {
		order: server.Sort_Order
		column := table.columns[r.sort_by_column.?]
		property_id := cast(Track_Property_ID) r.sort_by_column.?

		switch r.sort_order {
			case .None, .Ascending: order = .Ascending
			case .Descending: order = .Descending
		}

		result.sort_spec = server.Track_Sort_Spec {
			metric = property_id,
			order = order,
		}
	}

	return
}

track_table_get_tracks :: proc(table: Track_Table) -> []Track_ID {
	ids := make([]Track_ID, len(table.rows))
	for row, i in table.rows {
		ids[i] = auto_cast row.id
	}

	return ids
}

track_table_get_selection :: proc(table: Track_Table) -> []Track_ID {
	ids: [dynamic]Track_ID

	for row in table.rows {
		if row.selected {
			append(&ids, cast(Track_ID) row.id)
		}
	}

	return ids[:]
}

track_table_process_result :: proc(
	table: Track_Table, result: Track_Table_Result,
	cl: ^Client, sv: ^Server, flags: Track_Table_Result_Process_Flags,
) {
	if result.play != nil {
		if .SetQueuePos in flags {
			server.set_queue_track(sv, result.play.?)
		}
		else {
			tracks := track_table_get_tracks(table)
			defer delete(tracks)
			server.play_playlist(sv, tracks, table.playlist_id, result.play.?)
		}
	}

	if result.play_selection {
		selection := track_table_get_selection(table)
		defer delete(selection)
		server.play_playlist(sv, selection, table.playlist_id)
	}
	
	if result.add_selection_to_queue {
		selection := track_table_get_selection(table)
		defer delete(selection)
		server.append_to_queue(sv, selection, table.playlist_id)
	}
}

track_table_show_context :: proc(
	table: Track_Table, table_result: Track_Table_Result,
	context_id: imgui.ID, flags: Track_Context_Flags, sv: Server,
) -> (result: Track_Context_Result, shown: bool) #optional_ok {
	imgui.BeginPopupEx(context_id, {.AlwaysAutoResize} | imgui.WindowFlags_NoDecoration) or_return
	defer imgui.EndPopup()
	shown = true

	if table_result.context_menu_target != nil {
		track_id := table_result.context_menu_target.?
		result.single_track = track_id
		show_track_context_items(track_id, &result, sv.library)
	}
	
	if .NoRemove not_in flags && imgui.MenuItem("Remove") {
		result.remove = true
	}

	if .NoQueue not_in flags {
		result.play |= imgui.MenuItem("Play", "Ctrl + P")
		result.add_to_queue |= imgui.MenuItem("Add to queue", "Ctrl + Q")
	}

	if .NoEditMetadata not_in flags {
		result.edit_metadata |= imgui.MenuItem("Edit metadata")
	}

	return
}

track_table_process_context :: proc(
	table: Track_Table, table_result: Track_Table_Result,
	result: Track_Context_Result, cl: ^Client, sv: ^Server,
) {
	if result.single_track != nil {
		process_track_context(result.single_track.?, result, cl, sv, table.playlist_id, false)
	}
	else {
		if result.play {
			selection := track_table_get_selection(table)
			defer delete(selection)
			server.play_playlist(sv, selection, table.playlist_id)
		}
		if result.add_to_queue {
			selection := track_table_get_selection(table)
			defer delete(selection)
			server.append_to_queue(sv, selection, table.playlist_id)
		}
		if result.edit_metadata {
			selection := track_table_get_selection(table)
			defer delete(selection)
			if editor, ok := bring_window_to_front(cl, WINDOW_METADATA_EDITOR); ok {
				metadata_editor_window_select_tracks(auto_cast editor, selection)
			}
		}
	}

	if result.add_to_playlist != nil {
		playlist, _, playlist_found := server.library_get_playlist(sv.library, result.add_to_playlist.?)
		if playlist_found {
			selection := track_table_get_selection(table)
			defer delete(selection)
			server.playlist_add_tracks(playlist, &sv.library, selection)
		}
	}
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
