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

import "core:strings"
import "src:main/player"
import "src:imx"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"

folder_tree_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		selected_folder_serial: uint,
		displayed_folder:       ^lib.Folder,
		tree_serial:            uint,
		root_node:              ^lib.Folder,
		track_table:            Track_Table,
		tracks:                 [dynamic]lib.Track_ID,
	}

	if ev.type != .Show do return false

	_Events :: struct {
		select:       ^lib.Folder,
		play:         ^lib.Folder,
		add_to_queue: ^lib.Folder,
	}

	events: _Events

	COLUMN_NAME      :: 0
	COLUMN_LENGTH    :: 1
	COLUMN_FILE_SIZE :: 2
	COLUMN__COUNT    :: 3

	_show_folder_node_common :: proc(events: ^_Events, folder: ^lib.Folder) {
		if imgui.IsItemClicked(.Middle) {
			events.play = folder
		}

		if imgui.BeginPopupContextItem() {
			defer imgui.EndPopup()

			if imgui.MenuItem("Play") {
				events.play = folder
			}

			if imgui.MenuItem("Add to queue") {
				events.add_to_queue = folder
			}
		}
	}

	_show_folder_node :: proc(folder: ^lib.Folder, events: ^_Events) {
		imgui.TableNextRow()

		imgui.PushIDPtr(folder)
		defer imgui.PopID()

		if imgui.TableSetColumnIndex(COLUMN_LENGTH) {
			imx.text(64, folder.totals.length)
		}

		if imgui.TableSetColumnIndex(COLUMN_FILE_SIZE) {
			imx.textf(64, "%M", folder.totals.file_size)
		}

		if imgui.TableSetColumnIndex(COLUMN_NAME) {
			if folder.first_child != nil {
				if imgui.SmallButton(ICON_MAGNIFY) {
					events.select = folder
				}
				imgui.SetItemTooltip("View all contained tracks")
				imgui.SameLine()
			}

			if folder.uid != 0 && folder.uid == player.get_current_playlist() {
				imgui.TableSetBgColor(.RowBg0, get_theme_color(.PlayingHighlight))
			}

			folder_name := strings.clone_to_cstring(folder.name, get_frame_allocator())

			if folder.first_child != nil {
				if imgui.TreeNodeEx(folder_name, {.SpanAllColumns}) {
					defer imgui.TreePop()

					_show_folder_node_common(events, folder)

					for child := folder.first_child; child != nil; child = child.next {
						_show_folder_node(child, events)
					}
				}
				else do _show_folder_node_common(events, folder)
			}
			else {
				if imgui.Selectable(folder_name) {
					events.select = folder
				}

				_show_folder_node_common(events, folder)
			}
		}
	}

	_select_folder :: proc(f: ^lib.Folder) {
		clear(&w.tracks)
		track_table_free(&w.track_table)
		w.displayed_folder = f
		lib.find_folder_tracks(f, &w.tracks)
	}

	_get_first_folder_with_multiple_children :: proc(f: ^lib.Folder) -> ^lib.Folder {
		if f.child_count > 1 do return f
		else if f.child_count == 0 do return nil
		for child := f.first_child; child != nil; child = child.next {
			c := _get_first_folder_with_multiple_children(child)
			if c != nil do return c
		}
		return nil
	}

	if w.displayed_folder == nil {
		if w.tree_serial != lib.get_folder_tree_serial() {
			w.root_node = lib.get_root_folder()
		}

		if w.root_node == nil {
			imgui.TextDisabled("No local folders added")
			return false
		}

		if imgui.Button("Back") {
			w.displayed_folder = nil
			return true
		}

		flags := imgui.TableFlags_Resizable|
			imgui.TableFlags_Resizable|imgui.TableFlags_BordersInner|
			imgui.TableFlags_Hideable|imgui.TableFlags_SizingStretchProp|
			imgui.TableFlags_RowBg|imgui.TableFlags_ScrollY
		
		imgui.BeginTable("##folder_tree", COLUMN__COUNT, flags) or_return
		defer imgui.EndTable()

		root := _get_first_folder_with_multiple_children(w.root_node)
		if root == nil do root = w.root_node
		_show_folder_node(root, &events)

		if events.play != nil {
			_select_folder(events.play)
			player.play_playlist(w.tracks[:], events.play.uid)
		}

		if events.select != nil {
			_select_folder(events.select)
		}

		if events.add_to_queue != nil {
			tracks: [dynamic]lib.Track_ID
			defer delete(tracks)

			lib.find_folder_tracks(events.add_to_queue, &tracks)
			player.add_to_queue(tracks[:], events.add_to_queue.uid)
		}
	}
	else {
		if imgui.Button("Back") {
			w.displayed_folder = nil
			return true
		}

		track_table_update(&w.track_table, lib.get_tracks_serial(), w.tracks[:], w.displayed_folder.uid)
		track_table_show(&w.track_table, "##tracks", {.NoRemove})
	}

	return true
}
