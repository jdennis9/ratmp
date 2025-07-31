#+private
package client

import "core:mem"
import "core:log"
import "core:strings"
import "core:fmt"

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
}

@(private="file")
_rebuild_nodes :: proc(cl: ^Client, sv: ^Server) {
	state := &cl.windows.folders
	tree := &sv.library.folder_tree

	mem.dynamic_arena_destroy(&state.node_arena)
	mem.dynamic_arena_destroy(&state.string_arena)

	mem.dynamic_arena_init(&state.string_arena, )
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

_folders_window_show :: proc(cl: ^Client, sv: ^Server) {
	state := &cl.windows.folders

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
			
			if node.track_count == 0 {
				if !imgui.TableSetColumnIndex(0) {return}
				if imgui.TreeNodeEx(strings.unsafe_string_to_cstring(node.name), {.SpanAllColumns}) {
					for &child in node.children {
						if child.track_count == 0 {show_node(cl, sv, &child, depth + 1)}
					}
			
					for &child in node.children {
						if child.track_count != 0 {show_node(cl, sv, &child, depth + 1)}
					}
			
					imgui.TreePop()
				}
			}
			else {
				if !imgui.TableSetColumnIndex(0) {return}
				if playlist_id == sv.current_playlist_id {
					imgui.TableSetBgColor(
						.RowBg0, imgui.GetColorU32ImVec4(global_theme.custom_colors[.PlayingHighlight])
					)
				}

				if imgui.Selectable(
					strings.unsafe_string_to_cstring(node.name),
					node.id == state.sel_folder_id,
					{.SpanAllColumns}
				) {
					state.sel_folder_id = node.id
				}

				if _play_track_input_pressed() {
					if folder, folder_found := server.library_find_folder(sv.library, node.id); folder_found {
						server.play_playlist(sv, folder.tracks[:], playlist_id)
					}
					state.sel_folder_id = node.id
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
		sel_folder, sel_folder_found := server.library_find_folder(sv.library, state.sel_folder_id)
		
		if sel_folder_found {
			playlist_id := _folder_id_to_playlist_id(sel_folder.id)
			filter_cstring := cstring(&state.track_filter[0])
			context_id := imgui.GetID("##track_context")

			imgui.InputTextWithHint("##track_filter", "Filter", filter_cstring, auto_cast len(state.track_filter))

			_track_table_update(
				&state.track_table, sv.library.serial + state.track_table_serial, sv.library, sel_folder.tracks[:], playlist_id,
				string(filter_cstring)
			)

			table_result := _track_table_show(state.track_table, "##tracks", context_id, sv.current_track_id)
			_track_table_process_results(state.track_table, table_result, cl, sv, {})
			if table_result.sort_spec != nil {
				server.library_sort_tracks(sv.library, sel_folder.tracks[:], table_result.sort_spec.?)
				state.track_table_serial += 1
			}

			context_result := _track_table_show_context(state.track_table, table_result, context_id, {.NoRemove}, sv^)
			_track_table_process_context(state.track_table, table_result, context_result, cl, sv)
		}
	}
}

_folders_window_destroy :: proc(cl: ^Client) {
	state := &cl.windows.folders
	mem.dynamic_arena_destroy(&state.node_arena)
}
