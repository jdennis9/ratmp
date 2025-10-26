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

import "base:runtime"
import "core:slice"
import "core:time"
import "core:strings"
import "core:fmt"
import "core:hash/xxhash"
import "core:log"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

import "imx"

Track_Row :: struct {
	genre, artist, album: string,
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

Track_Table :: struct {
	rows: [dynamic]Track_Row,
	serial: uint,
	playlist_id: Global_Playlist_ID,
	filter_hash: u32,
	flags: Track_Table_Flags,
	jump_to_track: Maybe(int),
}

Track_Table_Result :: struct {
	play: Maybe(Track_ID),
	select: Maybe(Track_ID),
	context_menu: Maybe(Track_ID),
	selection_count: int,
	lowest_selection_index: int,
	sort_spec: Maybe(server.Track_Sort_Spec),
	play_selection: bool,
	add_selection_to_queue: bool,
	pick_up_drag_drop_payload: []Track_ID,
	bounding_box: imgui.Rect,
}

track_table_free :: proc(table: ^Track_Table) {
	delete(table.rows)
	table.rows = nil
	table.serial = 0
}

track_table_get_selection :: proc(table: Track_Table, allocator := context.allocator) -> (ids: []Track_ID) {
	count := 0
	for row in table.rows {
		if row.selected {count += 1}
	}

	ids = make([]Track_ID, count, allocator)
	count = 0
	for row in table.rows {
		if row.selected {ids[count] = row.id; count += 1}
	}

	return
}

track_table_get_tracks :: proc(table: Track_Table, allocator := context.allocator) -> (ids: []Track_ID) {
	ids = make([]Track_ID, len(table.rows), allocator)
	for row, i in table.rows {
		ids[i] = row.id
	}
	return
}

track_table_update :: proc(
	table: ^Track_Table,
	serial: uint,
	lib: server.Library,
	tracks: []Track_ID,
	playlist_id: Global_Playlist_ID,
	filter: string,
	flags: Track_Table_Flags = {},
) {
	filter_hash := xxhash.XXH32(transmute([]u8) filter)
	table.flags = flags

	if table.serial == serial && table.playlist_id == playlist_id && table.filter_hash == filter_hash {return}
	log.debug("Serial", table.serial, "!=", serial)
	log.debug("Update track table for playlist ID", playlist_id)
	table.playlist_id = playlist_id
	table.serial = serial
	table.filter_hash = filter_hash

	track_to_row :: proc(lib: server.Library, id: Track_ID) -> (row: Track_Row, ok: bool) {
		track := server.library_find_track(lib, id) or_return
		md := track.properties

		row.id = id
		row.genre = md[.Genre].(string) or_else ""
		row.artist = md[.Artist].(string) or_else ""
		row.album = md[.Album].(string) or_else ""
		row.title = strings.unsafe_string_to_cstring(md[.Title].(string) or_else string(cstring("")))
		//row.year = auto_cast(md.values[.Year].(i64) or_else 0)
		row.track_num = auto_cast(md[.TrackNumber].(i64) or_else 0)
		row.bitrate = auto_cast(md[.Bitrate].(i64) or_else 0)

		duration := md[.Duration].(i64) or_else 0
		h, m, s := util.clock_from_seconds(auto_cast duration)
		row.duration_len = len(fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", h, m, s))
		fmt.bprintf(row.year_str[:], "%4d", md[.Year].(i64) or_else 0)

		year, month, day := time.date(time.unix(md[.DateAdded].(i64) or_else 0, 0))
		fmt.bprintf(row.date_added_str[:], "%4d-%2d-%2d", year, month, day)
		year, month, day = time.date(time.unix(md[.FileDate].(i64) or_else 0, 0))
		fmt.bprintf(row.file_date_str[:], "%4d-%2d-%2d", year, month, day)

		ok = true
		return
	}

	if filter == "" {
		clear(&table.rows)
		for track in tracks {
			row := track_to_row(lib, track) or_continue
			append(&table.rows, row)
		}
	}
	else {
		filtered: [dynamic]Track_ID
		defer delete(filtered)
		clear(&table.rows)
		spec := server.Track_Filter_Spec {
			components = ~{},
			filter = filter,
		}
		server.filter_tracks(lib, spec, tracks, &filtered)

		for track in filtered {
			row := track_to_row(lib, track) or_continue
			append(&table.rows, row)
		}
	}
}

track_table_show :: proc(
	table: Track_Table,
	str_id: cstring,
	context_menu_id: imgui.ID,
	playing: Track_ID,
) -> (result: Track_Table_Result) {
	list_clipper: imgui.ListClipper
	first_selected_row: Maybe(int)
	jump_to_track: Maybe(int)

	window_focused := imgui.IsWindowFocused({.ChildWindows})

	table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_Hideable|
		imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Reorderable|imgui.TableFlags_RowBg|
		imgui.TableFlags_ScrollY

	if .NoSort not_in table.flags {
		table_flags |= imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate
	}

	result.lowest_selection_index = max(type_of(result.lowest_selection_index))
	defer if result.lowest_selection_index == max(type_of(result.lowest_selection_index)) {
		result.lowest_selection_index = 0
	}

	column_flags := #partial [Track_Property_ID]imgui.TableColumnFlags {
		.Title = {.NoHide},
		.Bitrate = {.DefaultHide},
		.Year = {.DefaultHide},
		.TrackNumber = {.DefaultHide},
		.Genre = {.DefaultHide},
		.DateAdded = {.DefaultHide},
		.FileDate = {.DefaultHide},
	}

	imgui.TextDisabled("%u tracks", u32(len(table.rows)))

	if !imgui.BeginTable(str_id, len(Track_Property_ID), table_flags) {return}
	defer imgui.EndTable()

	result.bounding_box.Min = imgui.GetWindowPos();
	result.bounding_box.Max = result.bounding_box.Min + imgui.GetWindowSize();

	for component in Track_Property_ID {
		imgui.TableSetupColumn(server.TRACK_PROPERTY_NAMES[component], column_flags[component])
	}

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	// Sorting
	table_sort_specs := imgui.TableGetSortSpecs(); 
	if table_sort_specs != nil && table_sort_specs.Specs != nil && table_sort_specs.SpecsDirty {
		table_spec := table_sort_specs.Specs
		spec: server.Track_Sort_Spec
		spec.metric = auto_cast table_spec.ColumnIndex
		switch table_spec.SortDirection {
			case .Descending, .None: spec.order = .Descending
			case .Ascending: spec.order = .Ascending
		}

		table_sort_specs.SpecsDirty = false
		result.sort_spec = spec
	}

	// Handle hotkeys
	if window_focused {
		// Jump to track on Ctrl + Space
		if is_key_chord_pressed(.ImGuiMod_Ctrl, .Space) {
			for row, index in table.rows {
				if row.id == playing {
					jump_to_track = index
					break
				}
			}
		}

		if is_key_chord_pressed(.ImGuiMod_Ctrl, .A) {
			for &row in table.rows {
				row.selected = true
			}
		}

		result.play_selection |= is_key_chord_pressed(.ImGuiMod_Ctrl, .P)
		result.add_selection_to_queue |= is_key_chord_pressed(.ImGuiMod_Ctrl, .Q)
	}

	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows))
	defer imgui.ListClipper_End(&list_clipper)

	if jump_to_track != nil {
		imgui.ListClipper_IncludeItemByIndex(&list_clipper, auto_cast jump_to_track.?)
	}

	for imgui.ListClipper_Step(&list_clipper) {
		for display_index in list_clipper.DisplayStart..<list_clipper.DisplayEnd {
			index := int(display_index)
			row := &table.rows[index]

			imgui.PushIDInt(auto_cast display_index)
			defer imgui.PopID()

			imgui.TableNextRow()

			if jump_to_track != nil && index == jump_to_track.? {
				imgui.SetScrollHereY()
			}
			
			if row.id == playing {
				imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(global_theme.custom_colors[.PlayingHighlight]))
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Artist) {
				imx.text_unformatted(row.artist)
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Album) {
				imx.text_unformatted(row.album)
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Genre) {
				imx.text_unformatted(row.genre)
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Duration) {
				imx.text_unformatted(string(row.duration_str[:row.duration_len]))
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Year) {
				imx.text_unformatted(string(row.year_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.DateAdded) {
				imx.text_unformatted(string(row.date_added_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.FileDate) {
				imx.text_unformatted(string(row.file_date_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Bitrate) {
				imx.text(12, row.bitrate, "kb/s")
			}

			if imgui.TableSetColumnIndex(auto_cast Track_Property_ID.Title) {
				select: bool
				keep_selection: bool

				select |= imgui.Selectable(row.title, row.selected, {.SpanAllColumns})
				
				if imgui.BeginDragDropSource() {
					tracks := track_table_get_selection(table)
					_set_track_drag_drop_payload(tracks)
					delete(tracks)
					imgui.EndDragDropSource()
				}

				if is_play_track_input_pressed() {
					result.play = row.id
					select = true
				}

				if imgui.IsItemClicked(.Right) {
					imgui.OpenPopupID(context_menu_id)
					result.context_menu = row.id
					select = true
					keep_selection = true
				}

				// Selection logic
				if select {
					ctrl := imgui.IsKeyDown(.ImGuiMod_Ctrl)
					shift := imgui.IsKeyDown(.ImGuiMod_Shift)

					result.select = row.id

					if !ctrl && !shift {
						if !keep_selection || !row.selected {for &r in table.rows {r.selected = false}}
						row.selected = true
					}
					else if (ctrl && shift) || shift {
						lo := max(int)
						hi := -1
						for r, i in table.rows {
							if r.selected {
								if i < index {lo = min(lo, i)}
								if i > index {hi = max(hi, i)}
							}
						}

						if lo == max(int) && hi == -1 {
							for &r in table.rows[0:index+1] {r.selected = true}
						} else if hi == -1 {
							for &r in table.rows[lo:index+1] {r.selected = true}
						} else if lo == max(int) {
							for &r in table.rows[index+1:hi] {r.selected = true}
						} else if ((hi-index) < (index-lo)) {
							for &r in table.rows[index:hi+1] {r.selected = true}
						} else {
							for &r in table.rows[lo:index+1] {r.selected = true}
						}
					}
					else if ctrl {
						row.selected = true
					}
				}

				if row.selected {
					first_selected_row = first_selected_row == nil ? int(index) : min(first_selected_row.?, int(index))
					result.lowest_selection_index = min(result.lowest_selection_index, index)
					result.selection_count += 1
				}
			}
		}
	}

	return
}

Track_Table_Result_Process_Flag :: enum {
	// Tells proc to try set the queue position to a track when trying to play it, 
	// rather than queueing the entire playlist
	SetQueuePos,
}
Track_Table_Result_Process_Flags :: bit_set[Track_Table_Result_Process_Flag]

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

track_table_accept_drag_drop :: proc(result: Track_Table_Result, allocator: runtime.Allocator) -> (payload: []Track_ID, have_payload: bool) {
	imgui.BeginDragDropTargetCustom(result.bounding_box, imgui.GetID("foo")) or_return
	defer imgui.EndDragDropTarget()

	return get_track_drag_drop_payload(allocator)
}

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
		for id, playlist in lib.playlists {
			if imgui.MenuItem(playlist.name_cstring) {
				result.add_to_playlist = id
			}
		}
		imgui.EndMenu()
	}
}

track_table_show_context :: proc(
	table: Track_Table, table_result: Track_Table_Result,
	context_id: imgui.ID, flags: Track_Context_Flags, sv: Server,
) -> (result: Track_Context_Result, shown: bool) #optional_ok {
	if table_result.selection_count == 0 {return}
	imgui.BeginPopupEx(context_id, {.AlwaysAutoResize} | imgui.WindowFlags_NoDecoration) or_return
	defer imgui.EndPopup()
	shown = true

	if table_result.selection_count == 1 {
		track_id := table.rows[table_result.lowest_selection_index].id
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
				if result.go_to_album {_go_to_album(cl, track.properties)}
				if result.go_to_artist {_go_to_artist(cl, track.properties)}
				if result.go_to_genre {_go_to_genre(cl, track.properties)}
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
		playlist, playlist_found := server.library_get_playlist(&sv.library, result.add_to_playlist.?)
		if track_found && playlist_found {
			server.playlist_add_tracks(playlist, &sv.library, {track_id})
		}
	}

	if result.more_info {
		// @TODO
		//cl.windows.metadata_popup_track = track_id
		//cl.windows.metadata_popup_show = true
	}
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
		playlist, playlist_found := server.library_get_playlist(&sv.library, result.add_to_playlist.?)
		if playlist_found {
			selection := track_table_get_selection(table)
			defer delete(selection)
			server.playlist_add_tracks(playlist, &sv.library, selection)
		}
	}
}
