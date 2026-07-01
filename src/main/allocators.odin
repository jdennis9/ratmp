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
package main

import "base:runtime"
import "core:mem"

_Any_Allocator :: union {
	^mem.Dynamic_Arena,
	^mem.Scratch,
}

_allocator_destroy :: proc(a: _Any_Allocator) {
	switch v in a {
	case ^mem.Dynamic_Arena:
		mem.dynamic_arena_destroy(v)
		free(v)
	case ^mem.Scratch:
		mem.scratch_destroy(v)
		free(v)
	}
}

Allocator_Map_Entry_Flag :: enum {IsTemp}
Allocator_Map_Entry_Flags :: bit_set[Allocator_Map_Entry_Flag]

Allocator_Map_Entry :: struct {
	allocator: _Any_Allocator,
	tracker:   ^mem.Tracking_Allocator,
	flags:     Allocator_Map_Entry_Flags,
}

Allocator_Map :: map[string]Allocator_Map_Entry

allocator_map_add :: proc(
	m:         ^Allocator_Map,
	name:      string,
	allocator: _Any_Allocator,
	iface:     mem.Allocator,
	flags:     Allocator_Map_Entry_Flags,
	ignore_bad_free := false
) -> mem.Allocator {
	iface := iface
	entry: Allocator_Map_Entry
	entry.allocator = allocator
	entry.flags = flags

	if global_command_opts.memory_debug {
		entry.tracker = new(mem.Tracking_Allocator)
		if ignore_bad_free {
			entry.tracker.bad_free_callback =  proc(
				_: ^mem.Tracking_Allocator, _: rawptr, _: runtime.Source_Code_Location
			) {}
		}
		mem.tracking_allocator_init(entry.tracker, iface, runtime.heap_allocator())
		iface = mem.tracking_allocator(entry.tracker)
	}

	m[name] = entry

	return iface
}

allocator_map_add_dynamic_arena :: proc(
	m:    ^Allocator_Map,
	name: string,
	block_size := mem.DYNAMIC_ARENA_BLOCK_SIZE_DEFAULT,
	flags: Allocator_Map_Entry_Flags = {},
) -> mem.Allocator {
	arena := new(mem.Dynamic_Arena)
	mem.dynamic_arena_init(arena, block_size=block_size)
	allocator := mem.dynamic_arena_allocator(arena)

	return allocator_map_add(m, name, arena, allocator, flags)
}

allocator_map_add_heap :: proc(m: ^Allocator_Map, name: string, flags: Allocator_Map_Entry_Flags = {}) -> mem.Allocator {
	return allocator_map_add(m, name, nil, runtime.default_allocator(), flags)
}

allocator_map_add_scratch :: proc(
	m:                ^Allocator_Map,
	name:             string,
	size:             int,
	backup_allocator: mem.Allocator,
	flags:            Allocator_Map_Entry_Flags = {}
) -> mem.Allocator {
	s := new(mem.Scratch)
	mem.scratch_init(s, size, backup_allocator)
	return allocator_map_add(m, name, s, mem.scratch_allocator(s), flags, ignore_bad_free=true)
}
