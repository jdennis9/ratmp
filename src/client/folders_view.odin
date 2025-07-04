#+private file
package client

import "core:mem"
import "core:path/filepath"
import "core:log"
import "core:strings"
import "core:slice"
import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

_Folder_Node :: struct {
	child_names: [dynamic]string,
	children: [dynamic]_Folder_Node,
	playlist_id: Playlist_ID,
	duration_str: [10]u8,
	duration_str_len: int,
	track_count: i32,
	open: bool,
}

@private
_Folders_View :: struct {
	serial: uint,
	node_arena: mem.Dynamic_Arena,
	string_arena: mem.Dynamic_Arena,
	root: _Folder_Node,
	track_table: _Track_Table_2,
	sel_playlist_id: Playlist_ID,
	filter: [128]u8,
}

@private
_update_folders_view :: proc(cl: ^Client, sv: ^Server) {
	state := &cl.folders_view
	
	if sv.library.serial == cl.folders_view.serial {return}
	state.root.child_names = nil
	state.root.children = nil
	state.root.playlist_id = {}

	// Rebuild folder tree
	view := &cl.folders_view
	view.serial = sv.library.serial

	node_allocator := mem.dynamic_arena_allocator(&state.node_arena)
	string_allocator := mem.dynamic_arena_allocator(&state.string_arena)
	
	mem.dynamic_arena_destroy(&state.node_arena)
	mem.dynamic_arena_init(&state.node_arena, alignment=64)
	mem.dynamic_arena_destroy(&state.string_arena)
	mem.dynamic_arena_init(&state.string_arena, alignment=64)

	add_child :: proc(parent: ^_Folder_Node, name: string, node_allocator: mem.Allocator, string_allocator: mem.Allocator) -> int {
		if index, exists := slice.linear_search(parent.child_names[:], name); exists {
			return index
		}

		if parent.children == nil {
			parent.child_names = make([dynamic]string, node_allocator)
			parent.children = make([dynamic]_Folder_Node, node_allocator)
		}

		index := len(parent.children)
		append(&parent.child_names, string(strings.clone_to_cstring(name, string_allocator)))
		append(&parent.children, _Folder_Node{})
		return index
	}

	for folder in sv.library.path_allocator.dirs {
		folder_name := string(folder.string_pool[:folder.name_length])
		parts := strings.split(folder_name, filepath.SEPARATOR_STRING)
		defer delete(parts)

		if len(parts) == 0 {continue}
		
		parent := &state.root
		parent_name := "<root>"
		for part in parts[:len(parts)-1] {
			index := add_child(parent, part, node_allocator, string_allocator)
			parent_name = parent.child_names[index]
			parent = &parent.children[index]
		}

		end_index := add_child(parent, parts[len(parts)-1], node_allocator, string_allocator)
		end := &parent.children[end_index]
		end.playlist_id = Playlist_ID {
			serial = auto_cast len(Metadata_Component),
			pool = server.library_hash_string(parts[len(parts)-1])
		}

		playlist := server.playlist_list_get(sv.library.categories.folders, end.playlist_id) or_continue

		h, m, s := util.clock_from_seconds(auto_cast playlist.duration)
		end.duration_str_len = len(fmt.bprintf(end.duration_str[:], "%02d:%02d:%02d", h, m, s))
		log.debug(string(end.duration_str[:]))
		end.track_count = auto_cast len(playlist.tracks)
	}
}

@private
_show_folders_window :: proc(cl: ^Client, sv: ^Server) {
	_update_folders_view(cl, sv)
	root_name: cstring = "<filesystem root>"

	root_table_flags := imgui.TableFlags_BordersV|imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Resizable

	if !imgui.BeginTable("##folders", 2, root_table_flags) {return}
	defer imgui.EndTable()

	state := &cl.folders_view

	imgui.TableNextRow()

	if imgui.TableSetColumnIndex(0) {
		prev_root: ^_Folder_Node
		root := &state.root

		if len(root.children) == 0 {return}
		for len(root.children) == 1 {
			prev_root = root
			root_name = strings.unsafe_string_to_cstring(root.child_names[0])
			root = &root.children[0]
		}

		show_node :: proc(cl: ^Client, sv: ^Server, root_name: string, root: ^_Folder_Node, depth: int) {
			state := &cl.folders_view
			imgui.TableNextRow()
			
			if root.playlist_id.serial == 0 {
				if !imgui.TableSetColumnIndex(0) {return}
				if imgui.TreeNodeEx(strings.unsafe_string_to_cstring(root_name), {.SpanAllColumns}) {
					for node_name, index in root.child_names {
						node := &root.children[index]
						if node.playlist_id == {} {show_node(cl, sv, node_name, node, depth + 1)}
					}
			
					for node_name, index in root.child_names {
						node := &root.children[index]
						if node.playlist_id != {} {show_node(cl, sv, node_name, node, depth + 1)}
					}
					imgui.TreePop()
				}
			}
			else {
				if !imgui.TableSetColumnIndex(0) {return}
				if root.playlist_id == sv.current_playlist_id {
					imgui.TableSetBgColor(
						.RowBg0, imgui.GetColorU32ImVec4(cl.theme.custom_colors[.PlayingHighlight])
					)
				}

				if imgui.Selectable(
					strings.unsafe_string_to_cstring(root_name),
					root.playlist_id == state.sel_playlist_id,
					{.SpanAllColumns}
				) {
					state.sel_playlist_id = root.playlist_id
				}

				if _play_track_input_pressed() {
					if 
					playlist, playlist_found := server.playlist_list_get(sv.library.categories.folders, root.playlist_id);
					playlist_found {
						server.play_playlist(sv, playlist.tracks[:], playlist.id)
					}
				}

				if imgui.TableSetColumnIndex(1) {
					_native_text_unformatted(string(root.duration_str[:root.duration_str_len]))
				}

				if imgui.TableSetColumnIndex(2) {
					buf: [8]u8
					_native_text(&buf, root.track_count)
				}
			}
		}

		if imgui.BeginTable("##folders", 3, imgui.TableFlags_RowBg|imgui.TableFlags_BordersInner) {
			imgui.TableSetupColumn("Folder")
			imgui.TableSetupColumn("Duration")
			imgui.TableSetupColumn("No. Tracks")
			imgui.TableSetupScrollFreeze(1, 1)
			imgui.TableHeadersRow()
			show_node(cl, sv, string(root_name), root, 0)
			imgui.EndTable()
		}
	}

	if state.sel_playlist_id != {} && imgui.TableSetColumnIndex(1) {
		playlist, playlist_found := server.playlist_list_get(sv.library.categories.folders, state.sel_playlist_id)
		if playlist_found {
			filter := cstring(&state.filter[0])
			context_id := imgui.GetID("##track_context")

			_track_table_update(
				&state.track_table, sv.library.serial, sv.library, playlist.tracks[:], state.sel_playlist_id,
				string(filter)
			)

			table_result := _track_table_show(state.track_table, "##tracks", cl.theme, context_id, sv.current_track_id)
			_track_table_process_results(state.track_table, table_result, cl, sv, {})
			if table_result.sort_spec != nil {server.playlist_sort(playlist, sv.library, table_result.sort_spec.?)}

			context_result := _track_table_show_context(state.track_table, table_result, context_id, {}, sv^)
			_track_table_process_context(state.track_table, table_result, context_result, cl, sv)
		}
	}
}
