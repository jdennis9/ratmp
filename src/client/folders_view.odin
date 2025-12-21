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
#+private file
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

@private
Folders_Window :: struct {
	using base: Window_Base,
	track_filter: [128]u8,
	serial: uint,
	node_arena: mem.Dynamic_Arena,
	string_arena: mem.Dynamic_Arena,
	node_allocator: mem.Allocator,
	string_allocator: mem.Allocator,
	sel_folder_id: u32,
	track_table: Track_Table,
	track_table_serial: uint,
	root: _Folder_Node,
	viewing_tracks: []Track_ID,
	viewing_tracks_serial: uint,
	viewing_folder_name: [128]u8,
	sbs_mode: Side_By_Side_Window_Mode,
}

_rebuild_nodes :: proc(state: ^Folders_Window, cl: ^Client, sv: ^Server) {
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

_folder_id_to_playlist_id :: proc(id: u32) -> Global_Playlist_ID {
	return {id = auto_cast id, origin = .Folder}
}

_set_viewing_tracks :: proc(state: ^Folders_Window, cl: ^Client, tracks: []Track_ID) {
	delete(state.viewing_tracks)
	state.viewing_tracks = slice.clone(tracks)
	state.viewing_tracks_serial = 0
}

@private
FOLDERS_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Folders",
	internal_name = WINDOW_FOLDERS,
	make_instance = folders_window_make_instance,
	show = folders_window_show,
	hide = folders_window_hide,
}

@private
folders_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Folders_Window, allocator)
}

@private
folders_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Folders_Window) self

	_Node_Result :: struct {
		play: ^_Folder_Node,
		select: ^_Folder_Node,
		remove: ^_Folder_Node,
	}

	select_folder :: proc(state: ^Folders_Window, lib: Library, node: _Folder_Node) -> bool {
		folder := server.library_find_folder(lib, node.id) or_return
		delete(state.viewing_tracks)
		log.debug(folder)
		state.viewing_tracks = server.library_folder_tree_recurse_tracks(lib, folder^, context.allocator)
		state.sel_folder_id = node.id
		state.viewing_folder_name[copy(state.viewing_folder_name[:len(state.viewing_folder_name)-1], node.name)] = 0
		return true
	}

	play_folder :: proc(sv: ^Server, node: _Folder_Node) {
		if folder, found := server.library_find_folder(sv.library, node.id); found {
			tracks := server.library_folder_tree_recurse_tracks(sv.library, folder^, context.allocator)
			server.play_playlist(sv, tracks, _folder_id_to_playlist_id(node.id))
			delete(tracks)
		}
	}

	show_node :: proc(
		state: ^Folders_Window,
		cl: ^Client, sv: ^Server,
		node: ^_Folder_Node,
		depth: int,
		result: ^_Node_Result,
	) {
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
					result.select = node
				}

				if imgui.BeginPopupContextItem() {
					if imgui.MenuItem("Remove from library") {
						result.remove = node
					}
					imgui.EndPopup()
				}

				if is_play_track_input_pressed() {
					result.select = node
					result.play = node
				}

				for &child in node.children {
					if child.track_count == 0 {show_node(state, cl, sv, &child, depth + 1, result)}
				}
		
				for &child in node.children {
					if child.track_count != 0 {show_node(state, cl, sv, &child, depth + 1, result)}
				}
		
				imgui.TreePop()
			}
			else if is_play_track_input_pressed() {
				result.select = node
				result.play = node
			}
		}
		else {
			if !imgui.TableSetColumnIndex(0) {return}

			if imgui.Selectable(
				strings.unsafe_string_to_cstring(node.name),
				node.id == state.sel_folder_id,
				{.SpanAllColumns}
			) {
				result.select = node
			}

			if imgui.BeginPopupContextItem() {
				if imgui.MenuItem("Remove from library") {}
				imgui.EndPopup()
			}

			if is_play_track_input_pressed() {
				if folder, folder_found := server.library_find_folder(sv.library, node.id); folder_found {
					server.play_playlist(sv, folder.tracks[:], playlist_id)
				}
				result.select = node
			}

			if imgui.TableSetColumnIndex(1) {
				imx.text_unformatted(string(node.duration_str[:node.duration_str_len]))
			}

			if imgui.TableSetColumnIndex(2) {
				imx.text(8, node.track_count)
			}
		}
	}

	if state.serial != sv.library.serial {
		log.debug("Rebuilding folder tree...")
		state.serial = sv.library.serial
		_rebuild_nodes(state, cl, sv)
	}

	show_folders :: proc(data: rawptr, cl: ^Client, sv: ^Server) {
		state := cast(^Folders_Window) data
		prev_root: ^_Folder_Node
		root := &state.root

		if len(root.children) == 0 {return}
		for len(root.children) == 1 {
			prev_root = root
			root = &root.children[0]
		}

		imgui.TextDisabled("%d items", i32(len(root.children)))

		if imgui.BeginTable("##folders", 3, imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner|imgui.TableFlags_ScrollY) {
			result: _Node_Result
			imgui.TableSetupColumn("Folder")
			imgui.TableSetupColumn("Duration")
			imgui.TableSetupColumn("No. Tracks")
			imgui.TableSetupScrollFreeze(1, 1)
			imgui.TableHeadersRow()
			show_node(state, cl, sv, root, 0, &result)
			if result.select != nil {
				select_folder(state, sv.library, result.select^)
			}
			if result.play != nil {
				play_folder(sv, result.play^)
			}
			if result.remove != nil {
				server.library_remove_folder(&sv.library, result.remove.id)
			}
			imgui.EndTable()
		}
	}

	show_tracks :: proc(data: rawptr, cl: ^Client, sv: ^Server) {
		state := cast(^Folders_Window) data

		if state.sel_folder_id == 0 {return}

		playlist_id := _folder_id_to_playlist_id(state.sel_folder_id)
		filter_cstring := cstring(&state.track_filter[0])
		context_id := imgui.GetID("##track_context")

		imgui.InputTextWithHint("##track_filter", "Filter", filter_cstring, auto_cast len(state.track_filter))

		track_table_update(
			cl^,
			&state.track_table, sv.library.serial + state.track_table_serial,
			sv.library, state.viewing_tracks[:], playlist_id,
			string(filter_cstring)
		)

		imgui.TextDisabled("%s", cstring(&state.viewing_folder_name[0]))

		table_result := track_table_show(state.track_table, "##tracks", context_id, sv.current_track_id)
		track_table_process_result(state.track_table, table_result, cl, sv, {})
		if table_result.sort_spec != nil {
			server.library_sort_tracks(sv.library, state.viewing_tracks[:], table_result.sort_spec.?)
			state.track_table_serial += 1
		}

		context_result := track_table_show_context(state.track_table, table_result, context_id, {.NoRemove}, sv^)
		track_table_process_context(state.track_table, table_result, context_result, cl, sv)
	}

	sbs: Side_By_Side_Window

	sbs.left_proc = show_folders
	sbs.right_proc = show_tracks
	sbs.mode = state.sbs_mode
	sbs.data = state
	sbs.focus_right = state.sel_folder_id != 0

	result := side_by_side_window_show(sbs, cl, sv)
	state.sbs_mode = result.mode

	if result.go_back {
		state.sel_folder_id = 0
	}
}

folders_window_hide :: proc(self: ^Window_Base) {
	state := cast(^Folders_Window) self
	
	track_table_free(&state.track_table)
}

folders_window_free :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Folders_Window) self

	mem.dynamic_arena_destroy(&state.node_arena)
	mem.dynamic_arena_destroy(&state.string_arena)
	delete(state.viewing_tracks)
	state.viewing_tracks = nil
	state.viewing_tracks_serial = 0
	state.serial = 0
	state.root = {}
}
