
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
#+private file
package client

import "src:main/player"
import "core:slice"
import "core:hash"
import "src:imx"
import "core:time"
import "core:fmt"
import "core:strings"
import "src:main/shared"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

_Shared_Strings_Table_Row :: struct {
	name:          string,
	id:            lib.Shared_String_ID,
	uid:           shared.UID,
	duration_str:  [12]u8,
	file_size_str: [8]u8,
	length_str:    [8]u8,
	totals:        lib.Track_Totals,
	selected:      bool,
}

_Shared_Strings_Window :: struct {
	type:             lib.Shared_String_Type,
	filter_buf:       [128]u8,
	filter_hash:      u64,
	table_rows:       []_Shared_Strings_Table_Row,
	rows_serial:      uint,
	sort_serial:      uint,
	sort_spec_serial: uint,
	sort_spec:        Maybe(lib.Playlist_Sort_Spec),
	viewing:          Maybe(lib.Shared_String_ID),
	track_table:      Track_Table,
	track_table_id:   lib.Shared_String_ID,
}

_build_table :: proc(w: ^_Shared_Strings_Window) {
	shared.TIME_SCOPE("Build shared string table")

	delete(w.table_rows)

	frame_allocator_guard()

	type := w.type
	w.table_rows = nil
	temp_allocator := get_frame_allocator()

	all_strings  := slice.clone(lib.get_all_shared_strings(type), temp_allocator)	
	filter_str   := string(cstring(&w.filter_buf[0]))
	filter_lower := strings.to_lower(filter_str, temp_allocator)
	totals       := make([]lib.Track_Totals, len(all_strings), temp_allocator)
	
	w.table_rows = make([]_Shared_Strings_Table_Row, len(all_strings))
	iter := lib.make_track_iterator()

	switch type {
	case .Artist:
		for track in lib.iterate_tracks(&iter) {
			for id in track.artists {
				lib.add_to_track_totals(&totals[id], track^)
			}
		}
	case .Genre:
		for track in lib.iterate_tracks(&iter) {
			for id in track.genres {
				lib.add_to_track_totals(&totals[id], track^)
			}
		}
	case .Album:
		for track in lib.iterate_tracks(&iter) {
			if track.album != nil {
				id := track.album.?
				lib.add_to_track_totals(&totals[id], track^)
			}
			else {
				// @TODO: Consider tracks with no album
			}
		}
	}

	out_index := 0
	row_count := 0

	for in_index := 0; in_index < len(all_strings); in_index += 1 {		
		if !strings.contains(all_strings[in_index].lower_name, filter_lower) {
			continue
		}
		
		row := &w.table_rows[out_index]
		row.id     = auto_cast in_index
		row.name   = all_strings[in_index].name
		row.uid    = all_strings[in_index].uid
		row.totals = totals[in_index]
		
		h, m, s := time.clock_from_seconds(auto_cast row.totals.duration)
		
		fmt.bprint(row.length_str[:], row.totals.length)
		fmt.bprintf(row.file_size_str[:], "%M", row.totals.file_size)
		fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", h, m, s)
		out_index += 1
	}

	w.table_rows = w.table_rows[:out_index]

	if w.sort_spec != nil do lib.sort_by_totals(w.table_rows[:], w.sort_spec.?)
}

_show_top_table :: proc(w: ^_Shared_Strings_Window) -> bool {
	// --------------------------------------------------------------------------
	// Filter
	// --------------------------------------------------------------------------

	imgui.InputTextWithHint("##filter", "Filter", cstring(&w.filter_buf[0]), auto_cast len(w.filter_buf))

	_Column_Index :: enum {
		Title,
		Length,
		Duration,
		FileSize,
	}

	_Column :: struct {
		title:       cstring,
		sort_metric: lib.Playlist_Sort_Metric,
		flags:       imgui.TableColumnFlags,
	}

	COLUMNS := [_Column_Index]_Column {
		.Title = _Column {
			title       = "Title",
			sort_metric = .Title,
			flags       = {.NoHide},
		},
		.Length = _Column {
			title       = "No. Tracks",
			sort_metric = .Length,
		},
		.Duration = _Column {
			title = "Total Duration",
			sort_metric = .Duration,
		},
		.FileSize = _Column {
			title = "Total File Size",
			sort_metric = .FileSize,
		},
	}

	check_table_size() or_return

	table_flags := imgui.TableFlags_RowBg | imgui.TableFlags_Sortable |
		imgui.TableFlags_Reorderable | imgui.TableFlags_Resizable | imgui.TableFlags_BordersInner |
		imgui.TableFlags_ScrollY | imgui.TableFlags_Resizable | imgui.TableFlags_SizingStretchProp

	imgui.BeginTable("##table", auto_cast len(COLUMNS), table_flags) or_return
	defer imgui.EndTable()

	playback_state := get_last_playback_state()
	temp_allocator := get_frame_allocator()

	list_clipper: imgui.ListClipper
	imgui.ListClipper_Begin(&list_clipper, auto_cast len(w.table_rows))
	defer imgui.ListClipper_End(&list_clipper)

	for col in COLUMNS {
		imgui.TableSetupColumn(col.title, col.flags)
	}

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	update_sort: if table_sort_specs := imgui.TableGetSortSpecs(); table_sort_specs != nil {
		specs := table_sort_specs.Specs
		if specs == nil || !table_sort_specs.SpecsDirty do break update_sort
		table_sort_specs.SpecsDirty = false
		column := COLUMNS[cast(_Column_Index) specs.ColumnIndex]

		switch specs.SortDirection {
		case .None:
			w.sort_spec = nil
		case .Ascending:
			w.sort_spec = lib.Playlist_Sort_Spec {
				metric = column.sort_metric,
				order  = .Ascending
			}
		case .Descending:
			w.sort_spec = lib.Playlist_Sort_Spec {
				metric = column.sort_metric,
				order  = .Descending,
			}
		}

		if w.sort_spec != nil {
			w.sort_spec_serial += 1
		}
	}

	actions: struct {
		play_row: Maybe(int),
		view_row: Maybe(int),
	}

	for imgui.ListClipper_Step(&list_clipper) {
		for row_index in list_clipper.DisplayStart..<list_clipper.DisplayEnd {
			row := &w.table_rows[row_index]

			imgui.TableNextRow()

			if playback_state.playlist == row.uid {
				imgui.TableSetBgColor(.RowBg0, get_theme_color(.PlayingHighlight))
			}
			
			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Title) {
				if imgui.Selectable(strings.clone_to_cstring(row.name, temp_allocator), row.selected, {.SpanAllColumns}) {
					select_table_rows(w.table_rows[:], auto_cast row_index, false)

					if !imgui.IsKeyDown(.ImGuiMod_Ctrl) && !imgui.IsKeyDown(.ImGuiMod_Shift) {
						actions.view_row = int(row_index)
					}
				}

				if imgui.IsItemClicked(.Middle) || imx.is_item_double_clicked() {
					actions.play_row = int(row_index)
				}
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Length) {
				imx.text_unformatted(shared.string_from_array(row.length_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Duration) {
				imx.text_unformatted(shared.string_from_array(row.duration_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.FileSize) {
				imx.text_unformatted(shared.string_from_array(row.file_size_str[:]))
			}
		}
	}

	if actions.play_row != nil {
		row    := w.table_rows[actions.play_row.?]
		tracks := make_dynamic_array_len_cap([dynamic]lib.Track_ID, 0, 1024, get_frame_allocator())

		lib.get_tracks_with_shared_string(w.type, row.id, &tracks)
		player.play_playlist(tracks[:], row.uid)
	}

	if actions.view_row != nil {
		row := w.table_rows[actions.view_row.?]
		w.viewing = row.id
	}

	return true
}

_show_proc :: proc(w: ^_Shared_Strings_Window, ev: UI_Window_Event) -> bool {
	if ev != .Show do return false

	tracks_serial := lib.get_tracks_serial()
	filter_hash := hash.fnv64a(transmute([]byte) shared.string_from_array(w.filter_buf[:]))

	if w.viewing != nil {
		
		serial     := lib.get_shared_string_serial(w.type, w.viewing.?)
		uid        := lib.get_shared_string_uid(w.type, w.viewing.?)
		up_to_date := track_table_is_up_to_date(&w.track_table, serial, uid)
		
		if !up_to_date || w.track_table_id != w.viewing.? {
			shared.TIME_SCOPE("Update shared string track table")

			w.track_table_id = w.viewing.?

			tracks: [dynamic]lib.Track_ID
			defer delete(tracks)

			lib.get_tracks_with_shared_string(w.type, w.viewing.?, &tracks)

			track_table_update(&w.track_table, serial, tracks[:], uid)
		}

		if imgui.Button("Back") || imgui.IsKeyPressed(.Escape) {
			w.viewing = nil
		}

		track_table_show(&w.track_table, "##tracks", {.NoRemove})
	}

	if w.viewing == nil {
		if w.rows_serial != tracks_serial || w.filter_hash != filter_hash || w.sort_serial != w.sort_spec_serial {
			w.rows_serial = tracks_serial
			w.filter_hash = filter_hash
			w.sort_serial = w.sort_spec_serial
			_build_table(w)
		}

		switch w.type {
		case .Artist: imx.title_text("Artists")
		case .Album: imx.title_text("Albums")
		case .Genre: imx.title_text("Genres")
		}

		_show_top_table(w)
	}

	return true
}

@private
artists_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: _Shared_Strings_Window
	w.type = .Artist
	return _show_proc(&w, ev)
}

@private
genres_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: _Shared_Strings_Window
	w.type = .Genre
	return _show_proc(&w, ev)
}

@private
albums_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: _Shared_Strings_Window
	w.type = .Album
	return _show_proc(&w, ev)
}
