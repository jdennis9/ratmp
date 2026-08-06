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

import "src:main/shared"
import "src:imx"
import "src:main/player"
import "core:strings"
import "core:time"
import "core:fmt"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

playlists_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		playlist_name_buf: [512]u8,
		viewing_playlist:  Maybe(lib.Playlist_ID),
		playlists_serial:  uint,
		playlist_rows:     [dynamic]_Row,
		track_table:       Track_Table,
	}

	if ev.type == .Free || ev.type == .Hidden {
		delete(w.playlist_rows)
		w.playlist_rows = nil
		w.playlists_serial = 0
	}

	if ev.type != .Show do return false

	_Row :: struct {
		name:         string,
		length_str:   [8]u8,
		duration_str: [12]u8,
		totals:       lib.Track_Totals,
		id:           lib.Playlist_ID,
	}
	_Column_Index :: enum {Name, Length, Duration,}
	_Column :: struct {name: cstring, flags: imgui.TableColumnFlags}

	@static columns := [_Column_Index]_Column {
		.Name     = {"Name",       {.NoHide}},
		.Length   = {"No. Tracks", {}},
		.Duration = {"Duration",   {}},
	}

	playlists_serial := lib.get_playlists_serial()
	temp_allocator   := get_frame_allocator()

	frame_allocator_guard()

	if playlists_serial != w.playlists_serial {
		w.playlists_serial = playlists_serial
		clear(&w.playlist_rows)
		iter := lib.make_playlist_iterator()

		for playlist in lib.iterate_playlists(&iter) {
			row: _Row
			row.id     = playlist.handle
			row.name   = playlist.name
			row.totals = lib.sum_track_totals(playlist.tracks[:])
			fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", time.clock_from_seconds(auto_cast row.totals.duration))
			fmt.bprint(row.length_str[:], len(playlist.tracks))

			append(&w.playlist_rows, row)
		}
	}

	if w.viewing_playlist == nil {
		new_playlist_name_cstring := cstring(&w.playlist_name_buf[0])
		imgui.InputTextWithHint("##playlist_name", "New playlist name", new_playlist_name_cstring, auto_cast len(w.playlist_name_buf))
		imgui.SameLine()
		imgui.BeginDisabled(w.playlist_name_buf[0] == 0)
		if imgui.Button("+ New playlist") {
			lib.create_playlist(string(new_playlist_name_cstring))
		}
		imgui.EndDisabled()

		table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_Hideable|
			imgui.TableFlags_Resizable|imgui.TableFlags_Sortable|
			imgui.TableFlags_SizingStretchProp|imgui.TableFlags_ScrollY

		imgui.BeginTable("Playlists", auto_cast len(_Column_Index), table_flags) or_return
		defer imgui.EndTable()

		for col in columns {
			imgui.TableSetupColumn(col.name, col.flags)
		}

		imgui.TableSetupScrollFreeze(1, 1)
		imgui.TableHeadersRow()

		for &row in w.playlist_rows {
			playlist := lib.get_playlist(row.id) or_continue

			imgui.PushIDPtr(playlist)
			defer imgui.PopID()

			imgui.TableNextRow()

			if playlist.uid == player.get_current_playlist() {
				imgui.TableSetBgColor(.RowBg0, get_theme_color(.PlayingHighlight))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Name) {
				name := strings.clone_to_cstring(row.name, temp_allocator)

				if imgui.Selectable(name, false, {.SpanAllColumns}) {
					w.viewing_playlist = row.id
				}

				if imgui.BeginDragDropTarget() {
					payload := get_track_drag_drop_payload(temp_allocator)
					if payload != nil do lib.add_to_playlist(row.id, payload)
					imgui.EndDragDropTarget()
				}

				if imgui.IsItemClicked(.Middle) {
					player.play_playlist(playlist.tracks[:], playlist.uid)
				}
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Length) {
				imx.text_unformatted(shared.string_from_array(row.length_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Duration) {
				imx.text_unformatted(shared.string_from_array(row.duration_str[:]))
			}
		}
	}
	else {
		if imgui.Button("Back") {
			w.viewing_playlist = nil
			return false
		}

		if playlist, ok := lib.get_playlist(w.viewing_playlist.?); ok {
			track_table_update(&w.track_table, playlist.serial, playlist.tracks[:], playlist.uid)
			events := track_table_show(&w.track_table, "##tracks", {})

			if events.remove_selection {
				selection := track_table_get_selection(w.track_table, temp_allocator)
				lib.remove_from_playlist(playlist.handle, selection)
			}

			if begin_window_drag_drop_target("##playlist_drag_drop") {
				defer imgui.EndDragDropTarget()

				payload := get_track_drag_drop_payload(temp_allocator)

				if payload != nil do lib.add_to_playlist(playlist.handle, payload)
			}
		}
		else {
			w.viewing_playlist = nil
			return false
		}
	}

	return true
}
