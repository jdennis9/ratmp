package main

import "base:runtime"
import sa "core:container/small_array"
import "core:mem"

_Any_Allocator :: union {
	^mem.Dynamic_Arena,
}

_allocator_destroy :: proc(a: _Any_Allocator) {
	switch v in a {
	case ^mem.Dynamic_Arena:
		mem.dynamic_arena_destroy(v)
		free(v)
	}
}

Allocator_Map_Entry :: struct {
	allocator: _Any_Allocator,
	tracker: ^mem.Tracking_Allocator,
}

Allocator_Map :: map[string]Allocator_Map_Entry

allocator_map_add :: proc(
	m: ^Allocator_Map,
	name: string,
	allocator: _Any_Allocator,
	iface: mem.Allocator
) -> mem.Allocator {
	iface := iface
	entry: Allocator_Map_Entry

	if global_command_opts.memory_debug {
		entry.tracker = new(mem.Tracking_Allocator)
		mem.tracking_allocator_init(entry.tracker, iface, runtime.heap_allocator())
		iface = mem.tracking_allocator(entry.tracker)
	}

	m[name] = entry

	return iface
}

allocator_map_add_dynamic_arena :: proc(
	m: ^Allocator_Map,
	name: string,
	block_size := mem.DYNAMIC_ARENA_BLOCK_SIZE_DEFAULT,
) -> mem.Allocator {
	arena := new(mem.Dynamic_Arena)
	mem.dynamic_arena_init(arena, block_size=block_size)
	allocator := mem.dynamic_arena_allocator(arena)

	return allocator_map_add(m, name, arena, allocator)
}
