#+private file
package client

import "core:mem"

import imgui "src:thirdparty/odin-imgui"

@private
_Folders_View :: struct {
	serial: uint,
}

_update_folders_view :: proc(cl: ^Client, sv: ^Server) {
	if sv.library.serial == cl.folders_view.serial {return}
	view := &cl.folders_view

	arena: mem.Dynamic_Arena
	allocator := mem.dynamic_arena_allocator(&arena)
	
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	
}

@private
_show_folders_window :: proc(cl: ^Client, sv: ^Server) {
	_update_folders_view(cl, sv)
}
