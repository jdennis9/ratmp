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
package library

import "src:main/util"
import "core:os"
import "core:fmt"
import "core:slice"
import "core:testing"
import "core:path/filepath"
import "base:runtime"
import "core:strings"
import "core:mem"

Folder :: struct {
	name:        string,
	parent:      ^Folder,
	next:        ^Folder,
	first_child: ^Folder,
	child_count: int,
	totals:      Track_Totals,
	uid:         util.UID,
}

@private
build_folder_tree :: proc(root: ^Folder, allocator: mem.Allocator) {
	iter := make_track_iterator()

	scratch: mem.Scratch
	mem.scratch_init(&scratch, 4<<10)
	defer mem.scratch_destroy(&scratch)

	temp_allocator := mem.scratch_allocator(&scratch)

	root^ = {}
	root.name = "<root>"
	root.uid = util.generate_uid()

	add :: proc(parent: ^Folder, name: string, track: Track, allocator: mem.Allocator) -> ^Folder {
		for h := parent.first_child; h != nil; h = h.next {
			if h.name == name {
				add_to_track_totals(&h.totals, track)
				return h
			}
		}

		folder        := new(Folder, allocator)
		folder.name   = strings.clone(name, allocator)
		folder.next   = parent.first_child
		folder.parent = parent
		folder.uid    = util.generate_uid()

		add_to_track_totals(&folder.totals, track)

		parent.first_child = folder
		parent.child_count += 1

		return folder
	}

	for track in iterate_tracks(&iter) {
		strings.starts_with(track.url, "file://") or_continue
		path := filepath.dir(strings.trim_prefix(track.url, "file://"))
		parts := strings.split_multi(path, {"/", "\\"}, temp_allocator) or_continue
		defer mem.scratch_free_all(&scratch)

		parent := root

		for part in parts {
			parent = add(parent, part, track^, allocator)
		}
	}
}

find_folder_tracks :: proc(folder: ^Folder, output: ^[dynamic]Track_ID) {
	scratch: mem.Scratch
	mem.scratch_init(&scratch, 4<<10)
	defer mem.scratch_destroy(&scratch)
	temp_allocator := mem.scratch_allocator(&scratch)

	parts := make_dynamic_array_len_cap([dynamic]string, 0, 128)
	defer delete(parts)

	for p := folder; p.parent != nil; p = p.parent {
		append(&parts, p.name)
	}

	slice.reverse(parts[:])

	path, _ := filepath.join(parts[:])
	defer delete(path)

	iter := make_track_iterator()

	for track in iterate_tracks(&iter) {
		mem.scratch_free_all(&scratch)

		strings.starts_with(track.url, "file://") or_continue
		track_folder := strings.trim_prefix(track.url, "file://")
		track_folder = filepath.clean(filepath.dir(track_folder), temp_allocator) or_continue

		if path == track_folder {
			append(output, track.handle)
		}
	}
}

@test
test_folder_tree :: proc(t: ^testing.T) {
	files := []string {
		"file://C:\\Music\\Mezzanine\\Mezzanine.mp3",
		"file://C:\\Music\\Mezzanine\\Teardrop.mp3",
		"file://C:\\Music\\Mezzanine\\BlackMilk.mp3",
		"file://C:\\Music\\Bloom\\Flame.mp3",
		"file://C:\\Music\\Bloom\\Purple.mp3",
	}

	testing.expect(t, init({}))
	defer shutdown()

	for f in files {
		add_track({title = "dont_care"}, f)
	}

	tree: Folder
	build_folder_tree(&tree, context.allocator)

	dump_folder :: proc(depth: int, folder: ^Folder) {
		for _ in 0..<depth do fmt.print("    ")

		fmt.println(folder.name)

		for h := folder.first_child; h != nil; h = h.next {
			dump_folder(depth + 1, h)
		}
	}

	dump_folder(0, &tree)
}
