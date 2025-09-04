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
import "core:log"
import "core:strings"
import "core:fmt"
import "core:slice"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

import "imx"

_Folder_Node :: struct {
	children: []_Folder_Node,
	name: string,
	duration_str_len: int,
	track_count: i32,
	id: u32,
	duration_str: [10]u8,
}

_Folders_Window :: struct {
	track_filter: [128]u8,
	serial: uint,
	node_arena: mem.Dynamic_Arena,
	string_arena: mem.Dynamic_Arena,
	node_allocator: mem.Allocator,
	string_allocator: mem.Allocator,
	sel_folder_id: u32,
	track_table: _Track_Table_2,
	track_table_serial: uint,
	root: _Folder_Node,
	viewing_tracks: []Track_ID,
	viewing_tracks_serial: uint,
}

@(private="file")
_rebuild_nodes :: proc(cl: ^Client, sv: ^Server) {
	state := &cl.windows.folders
	tree := &sv.library.folder_tree

	delete(state.viewing_tracks)
	state.viewing_tracks = nil

	mem.dynamic_arena_destroy(&state.node_arena)
	mem.dynamic_arena_destroy(&state.string_arena)

	mem.dynamic_arena_init(&state.string_arena)
	mem.dynamic_arena_init(&state.node_arena)
	state.string_allocator = mem.dynamic_arena_allocator(&state.string_arena)
	state.node_allocator = mem.dynamic_arena_allocator(&state.node_arena)

	library_folder_to_node :: proc(
		input: server.Library_Folder,
		folder_name: string,
		string_allocator, node_allocator: mem.Allocator,
	) -> (output: _Folder_Node) {
		output.id = input.id
		output.name = string(strings.clone_to_cstring(folder_name, string_allocator))
		output.children = make([]_Folder_Node, len(input.children), node_allocator)

		if len(input.tracks) > 0 {
			output.track_count = auto_cast len(input.tracks)
			h, m, s := util.clock_from_seconds(auto_cast input.duration)
			output.duration_str_len = len(fmt.bprintf(output.duration_str[:], "%02d:%02d:%02d", h, m, s))
		}

		for i in 0..<len(input.child_names) {
			output.children[i] = library_folder_to_node(
				input.children[i], input.child_names[i], string_allocator, node_allocator
			)
		}

		return
	}

	state.root = library_folder_to_node(
		tree.root_folder, "<root>", 
		state.string_allocator, state.node_allocator,
	)
}

@(private="file")
_folder_id_to_playlist_id :: proc(id: u32) -> Playlist_ID {
	return {serial = id, pool = auto_cast len(Metadata_Component)}
}

@(private="file")
_set_viewing_tracks :: proc(cl: ^Client, tracks: []Track_ID) {
	state := &cl.windows.folders
	delete(state.viewing_tracks)
	state.viewing_tracks = slice.clone(tracks)
	state.viewing_tracks_serial = 0
}

_folders_window_show :: proc(cl: ^Client, sv: ^Server) {
	state := &cl.windows.folders

	select_folder :: proc(cl: ^Client, sv: ^Server, node: _Folder_Node) -> bool {
		state := &cl.windows.folders
		folder := server.library_find_folder(sv.library, node.id) or_return
		delete(state.viewing_tracks)
		log.debug(folder)
		state.viewing_tracks = server.library_folder_tree_recurse_tracks(sv.library, folder^, context.allocator)
		state.sel_folder_id = node.id
		return true
	}

	play_folder :: proc(sv: ^Server, node: _Folder_Node) {
		if folder, found := server.library_find_folder(sv.library, node.id); found {
			tracks := server.library_folder_tree_recurse_tracks(sv.library, folder^, context.allocator)
			server.play_playlist(sv, tracks, _folder_id_to_playlist_id(node.id))
			delete(tracks)
		} else {log.error("FUUUU")}
	}

	if state.serial != sv.library.serial {
		log.debug("Rebuilding folder tree...")
		state.serial = sv.library.serial
		_rebuild_nodes(cl, sv)
	}

	root_table_flags := imgui.TableFlags_BordersInnerV|imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Resizable

	if !imgui.BeginTable("##folders", 2, root_table_flags) {return}
	defer imgui.EndTable()

	imgui.TableNextRow()

	if imgui.TableSetColumnIndex(0) {
		prev_root: ^_Folder_Node
		root := &state.root

		if len(root.children) == 0 {return}
		for len(root.children) == 1 {
			prev_root = root
			root = &root.children[0]
		}

		show_node :: proc(cl: ^Client, sv: ^Server, node: ^_Folder_Node, depth: int) {
			state := &cl.windows.folders
			playlist_id := _folder_id_to_playlist_id(node.id)
			imgui.TableNextRow()
			
			if playlist_id == sv.current_playlist_id {
				imgui.TableSetBgColor(
					.RowBg0, imgui.GetColorU32ImVec4(global_theme.custom_colors[.PlayingHighlight])
				)
			}

			if node.track_count == 0 {
				if !imgui.TableSetColumnIndex(0) {return}
				tree_node_flags := imgui.TreeNodeFlags{.SpanAllColumns}

				if state.sel_folder_id == node.id {tree_node_flags |= {.Selected}}
				if depth == 0 {tree_node_flags |= {.DefaultOpen}}

				if imgui.TreeNodeEx(strings.unsafe_string_to_cstring(node.name), tree_node_flags) {
					if imgui.IsItemToggledOpen() {
						select_folder(cl, sv, node^)
					}

					if _play_track_input_pressed() {
						select_folder(cl, sv, node^)
						play_folder(sv, node^)
					}

					for &child in node.children {
						if child.track_count == 0 {show_node(cl, sv, &child, depth + 1)}
					}
			
					for &child in node.children {
						if child.track_count != 0 {show_node(cl, sv, &child, depth + 1)}
					}
			
					imgui.TreePop()
				}
				else if _play_track_input_pressed() {
					select_folder(cl, sv, node^)
					play_folder(sv, node^)
				}
			}
			else {
				if !imgui.TableSetColumnIndex(0) {return}

				if imgui.Selectable(
					strings.unsafe_string_to_cstring(node.name),
					node.id == state.sel_folder_id,
					{.SpanAllColumns}
				) {
					select_folder(cl, sv, node^)
				}

				if _play_track_input_pressed() {
					if folder, folder_found := server.library_find_folder(sv.library, node.id); folder_found {
						server.play_playlist(sv, folder.tracks[:], playlist_id)
					}
					select_folder(cl, sv, node^)
				}

				if imgui.TableSetColumnIndex(1) {
					imx.text_unformatted(string(node.duration_str[:node.duration_str_len]))
				}

				if imgui.TableSetColumnIndex(2) {
					imx.text(8, node.track_count)
				}
			}
		}

		if imgui.BeginTable("##folders", 3, imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner) {
			imgui.TableSetupColumn("Folder")
			imgui.TableSetupColumn("Duration")
			imgui.TableSetupColumn("No. Tracks")
			imgui.TableSetupScrollFreeze(1, 1)
			imgui.TableHeadersRow()
			show_node(cl, sv, root, 0)
			imgui.EndTable()
		}
	}

	if state.sel_folder_id != 0 && imgui.TableSetColumnIndex(1) {
		playlist_id := _folder_id_to_playlist_id(state.sel_folder_id)
		filter_cstring := cstring(&state.track_filter[0])
		context_id := imgui.GetID("##track_context")

		imgui.InputTextWithHint("##track_filter", "Filter", filter_cstring, auto_cast len(state.track_filter))

		_track_table_update(
			&state.track_table, sv.library.serial + state.track_table_serial, sv.library, state.viewing_tracks[:], playlist_id,
			string(filter_cstring)
		)

		table_result := _track_table_show(state.track_table, "##tracks", context_id, sv.current_track_id)
		_track_table_process_results(state.track_table, table_result, cl, sv, {})
		if table_result.sort_spec != nil {
			server.library_sort_tracks(sv.library, state.viewing_tracks[:], table_result.sort_spec.?)
			state.track_table_serial += 1
		}

		context_result := _track_table_show_context(state.track_table, table_result, context_id, {.NoRemove}, sv^)
		_track_table_process_context(state.track_table, table_result, context_result, cl, sv)
		
	}
}

_folders_window_destroy :: proc(cl: ^Client) {
	state := &cl.windows.folders
	mem.dynamic_arena_destroy(&state.node_arena)
}
