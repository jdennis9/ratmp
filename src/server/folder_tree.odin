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
package server

import "core:mem"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import "core:fmt"
import "core:hash/xxhash"

Library_Folder_Tree :: struct {
	node_allocator: mem.Allocator,
	string_allocator: mem.Allocator,
	node_arena: mem.Dynamic_Arena,
	string_arena: mem.Dynamic_Arena,
	root_folder: Library_Folder,

	// For looking up folders by ID to avoid having to carry around
	// pointers in random places
	folder_ptrs: map[u32]^Library_Folder,
}

Library_Folder :: struct {
	child_names: [dynamic]string,
	children: [dynamic]Library_Folder,
	tracks: [dynamic]Track_ID,
	duration: int,
	id: u32,
}

@(private="file")
_hash_folder_id :: proc(parent_id: u32, name: string) -> u32 {
	return xxhash.XXH32(transmute([]u8)name, parent_id)
}

@(private="file")
_add_child :: proc(parent: ^Library_Folder, name: string, node_allocator, string_allocator: mem.Allocator) -> int {
	if index, exists := slice.linear_search(parent.child_names[:], name); exists {
		return index
	}

	base_id := parent.id

	if parent.children == nil {
		parent.child_names = make([dynamic]string, node_allocator)
		parent.children = make([dynamic]Library_Folder, node_allocator)
	}

	index := len(parent.children)
	append(&parent.child_names, string(strings.clone_to_cstring(name, string_allocator)))
	append(&parent.children, Library_Folder{id = _hash_folder_id(base_id, name)})
	return index
}

@(private="file")
_create_folder_lookup :: proc(table: ^map[u32]^Library_Folder, parent: ^Library_Folder) {
	//if len(parent.tracks) > 0 {
		table[parent.id] = parent
	//}

	for i in 0..<len(parent.children) {
		_create_folder_lookup(table, &parent.children[i])
	}

}

library_folder_print :: proc(name: string, folder: Library_Folder, depth: int) {
	for _ in 0..<depth {fmt.print('\t')}
	fmt.println(name, len(folder.tracks))

	for child in 0..<len(folder.child_names) {
		library_folder_print(folder.child_names[child], folder.children[child], depth+1)
	}
}

library_build_folder_tree :: proc(lib: ^Library) {
	tree := &lib.folder_tree

	log.debug("Building folder tree...")

	library_folder_tree_destroy(tree)
	library_folder_tree_init(tree)

	for track_id, track_index in lib.track_ids {
		path_buf: [512]u8
		md := lib.track_metadata[track_index]
		path := library_get_track_path(lib^, path_buf[:], track_id) or_continue
		library_folder_tree_add_track(tree, path, track_id, md)
	}

	_create_folder_lookup(&tree.folder_ptrs, &tree.root_folder)
}

library_folder_tree_init :: proc(tree: ^Library_Folder_Tree) {
	mem.dynamic_arena_init(&tree.node_arena)
	mem.dynamic_arena_init(&tree.string_arena)
	tree.node_allocator = mem.dynamic_arena_allocator(&tree.node_arena)
	tree.string_allocator = mem.dynamic_arena_allocator(&tree.string_arena)
}

library_folder_tree_add_track :: proc(tree: ^Library_Folder_Tree, path: string, track_id: Track_ID, track_metadata: Track_Metadata) {
	parts := strings.split(path, filepath.SEPARATOR_STRING)
	defer delete(parts)
	parent := &tree.root_folder

	if len(parts) == 0 {return}

	for part in parts[:len(parts)-1] {
		index := _add_child(parent, part, tree.node_allocator, tree.string_allocator)
		assert(index < len(parent.children))
		parent = &parent.children[index]
	}

	if parent.tracks == nil {parent.tracks = make([dynamic]Track_ID, tree.node_allocator)}
	append(&parent.tracks, track_id)
	parent.duration += int(track_metadata.values[.Duration].(i64) or_else 0)
}

library_folder_tree_destroy :: proc(tree: ^Library_Folder_Tree) {
	mem.dynamic_arena_destroy(&tree.node_arena)
	mem.dynamic_arena_destroy(&tree.string_arena)
	delete(tree.folder_ptrs)
	tree.node_arena = {}
	tree.string_arena = {}
	tree.root_folder = {}
	tree.folder_ptrs = nil
}

library_find_folder :: proc(lib: Library, id: u32) -> (ptr: ^Library_Folder, found: bool) {
	return lib.folder_tree.folder_ptrs[id]
}

library_folder_tree_count_tracks_recursively :: proc(lib: Library, folder: Library_Folder) -> int {
	count := len(folder.tracks)
	for child in folder.children {
		count += library_folder_tree_count_tracks_recursively(lib, child)
	}
	return count
}

library_folder_tree_copy_tracks_recursively :: proc(lib: Library, folder: Library_Folder, out: ^[dynamic]Track_ID) {
	for track in folder.tracks {append(out, track)}
	for child in folder.children {
		library_folder_tree_copy_tracks_recursively(lib, child, out)
	}
}

library_folder_tree_recurse_tracks :: proc(lib: Library, folder: Library_Folder, allocator: mem.Allocator) -> []Track_ID {
	count := library_folder_tree_count_tracks_recursively(lib, folder)
	if count == 0 {return nil}

	out: [dynamic]Track_ID = make([dynamic]Track_ID, allocator)
	reserve(&out, count)

	library_folder_tree_copy_tracks_recursively(lib, folder, &out)

	return out[:]
}

import "core:testing"
import "core:log"

@test
test_library_folder_tree :: proc(t: ^testing.T) {
	lib: Library
	tree: Library_Folder_Tree

	library_init(&lib, "")
	defer library_destroy(&lib)

	library_add_track(&lib, "/my/music/1.mp3", {})
	library_add_track(&lib, "/my/music/2.mp3", {})
	library_add_track(&lib, "/my/music/goodbye/1.mp3", {})
	library_add_track(&lib, "/my/music/goodbye/2.mp3", {})
	library_add_track(&lib, "/my/other/music/1.mp3", {})
	library_add_track(&lib, "/my/other/music/2.mp3", {})

	defer library_folder_tree_destroy(&tree)

	for track_id, track_index in lib.track_ids {
		path_buf: [512]u8
		md := lib.track_metadata[track_index]
		path := library_get_track_path(lib, path_buf[:], track_id) or_continue
		log.debug(path)
		library_folder_tree_add_track(&tree, path, track_id, md)
	}

	library_folder_print("<root>", tree.root_folder, 1)
}
