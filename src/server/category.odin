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
package server

import "core:slice"
import "core:strings"
import "core:mem"
import "core:sort"

Track_Category_Hash :: u32

Track_Category_Entry :: struct {
	hash: Track_Category_Hash,
	name: string,
	name_cstring: cstring,
	duration: i64,
	tracks: [dynamic]Track_ID,
	serial: uint,
}

Track_Category :: struct {
	arena: mem.Dynamic_Arena,
	auto_playlist_param_type: Playlist_Auto_Build_Param_Type,
	allocator: mem.Allocator,
	from_property: Track_Property_ID,
	entries: #soa[]Track_Category_Entry,
	serial: uint,
}

Track_Category_Entry_Ptr :: #soa^#soa[]Track_Category_Entry

track_category_hash_string :: library_hash_string

track_category_build_from_property :: proc(cat: ^Track_Category, lib: Library, property: Track_Property_ID, auto_playlist_param_type: Playlist_Auto_Build_Param_Type) {
	cat.from_property = property
	cat.serial = lib.serial

	mem.dynamic_arena_free_all(&cat.arena)
	mem.dynamic_arena_init(&cat.arena)
	cat.allocator = mem.dynamic_arena_allocator(&cat.arena)
	cat.auto_playlist_param_type = auto_playlist_param_type

	Entry_Info :: struct {
		name: cstring,
		count: i32,
	}

	entry_infos: map[Track_Category_Hash]Entry_Info
	defer delete(entry_infos)

	// Count how many entries there are
	for track in lib.tracks {
		property_value := track.properties[property].(string) or_continue
		property_hash := library_hash_string(property_value)
		if _, found := entry_infos[property_hash]; found {
			ei := &entry_infos[property_hash]
			ei.count += 1
		}
		else {
			entry_infos[property_hash] = Entry_Info {
				name = strings.clone_to_cstring(property_value, cat.allocator),
				count = 1,
			}
		}
	}

	if len(entry_infos) == 0 {
		return
	}

	cat.entries = make_soa_slice(#soa[]Track_Category_Entry, len(entry_infos))
	entry_index := 0

	// Add entries to category
	for entry_hash, entry_info in entry_infos {
		cat.entries[entry_index] = Track_Category_Entry {
			tracks = make_dynamic_array_len_cap([dynamic]Track_ID, 0, entry_info.count, cat.allocator),
			name_cstring = entry_info.name,
			name = string(entry_info.name),
			hash = entry_hash,
		}
		entry_index += 1
	}

	// Add tracks to entries
	for track in lib.tracks {
		property_value := track.properties[property].(string) or_continue
		property_hash := library_hash_string(property_value)
		entry_index = track_category_find_entry_index(cat, property_hash) or_else 0
		append(&cat.entries[entry_index].tracks, track.id)
		cat.entries[entry_index].duration += track.properties[.Duration].(i64) or_else 0
	}
}

track_category_find_entry_index :: proc(
	cat: ^Track_Category, hash: Track_Category_Hash
) -> (int, bool) {
	return slice.linear_search(cat.entries.hash[:len(cat.entries)], hash)
}

track_category_sort :: proc(
	lib: ^Library, cat: ^Track_Category, spec: Playlist_Sort_Spec,
) {
	iface: sort.Interface

	iface.collection = cat

	iface.swap = proc(it: sort.Interface, i, j: int) {
		cat := cast(^Track_Category) it.collection
		temp := cat.entries[i]
		cat.entries[i] = cat.entries[j]
		cat.entries[j] = temp
	}

	iface.len = proc(it: sort.Interface) -> int {
		return len((cast(^Track_Category)it.collection).entries)
	}

	switch spec.metric {
		case .Name: {
			iface.less = proc(it: sort.Interface, i, j: int) -> bool {
				cat := cast(^Track_Category) it.collection
				return strings.compare(cat.entries.name[i], cat.entries.name[j]) < 0
			}
		}
		case .Duration: {
			iface.less = proc(it: sort.Interface, i, j: int) -> bool {
				cat := cast(^Track_Category) it.collection
				return cat.entries.duration[i] < cat.entries.duration[j]
			}
		}
		case .Length: {
			iface.less = proc(it: sort.Interface, i, j: int) -> bool {
				cat := cast(^Track_Category) it.collection
				return len(cat.entries.tracks[i]) < len(cat.entries.tracks[j])
			}
		}
	}

	switch spec.order {
		case .Ascending:
			sort.reverse_sort(iface)
		case .Descending:
			sort.sort(iface)
	}

	cat.serial += 1
	lib.categories.serial += 1
}

track_category_entry_sort :: proc(
	lib: ^Library, cat: ^Track_Category, entry_index: int, spec: Track_Sort_Spec
) {
	library_sort_tracks(lib^, cat.entries[entry_index].tracks[:], spec)
	cat.entries[entry_index].serial += 1
}
