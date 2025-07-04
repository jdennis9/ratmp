#+private
package client

import "core:mem"
import "core:strings"
import "core:reflect"
import "core:log"

import "src:util"

/*@(private="file")
_Persistent_State_Font :: struct {
	path: string,
	size: f32,
	lang: Font_Languages,
}

@(private="file")
_Persistent_State :: struct {
	theme: string,
	background: string,
	enable_media_controls: bool,
	crop_album_art: bool,
	fonts: []_Persistent_State_Font,
	analysis: struct {
		spectrum_mode: _Spectrum_Display_Mode,
		spectrum_bands: int,
	},
}

_Persistent_State_Manager :: struct {
	arena_data: [2048]byte,
	arena: mem.Arena,
	allocator: mem.Allocator,
	saved_state: _Persistent_State,
}

@(private="file")
_get_persistent_state :: proc(client: Client, allocator: mem.Allocator) -> _Persistent_State {
	state: _Persistent_State

	state.theme = strings.clone(string(client.current_theme_name), allocator)
	state.background = strings.clone(client.background.path, allocator)
	state.enable_media_controls = client.enable_media_controls
	state.crop_album_art = client.metadata_window.crop_art
	state.analysis.spectrum_mode = client.analysis.spectrum_display_mode
	state.analysis.spectrum_bands = client.analysis.spectrum_bands

	return state
}

_persistent_state_update :: proc(client: ^Client) {
	mgr := &client.persistent_state_manager
	cur := _get_persistent_state(client^, context.temp_allocator)

	if mgr.allocator.procedure == nil {
		mem.arena_init(&mgr.arena, mgr.arena_data[:])
		mgr.allocator = mem.arena_allocator(&mgr.arena)
	}

	if !reflect.equal(mgr.saved_state, cur, true) {
		log.debug("Saving state", cur)
		free_all(mgr.allocator)
		mgr.saved_state = _get_persistent_state(client^, mgr.allocator)
	}
}

save_persistent_state :: proc(client: Client) {
	util.dump_json(_get_persistent_state(client, context.temp_allocator), client.paths.persistent_state)
}

load_persistent_state :: proc(client: ^Client) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	state: _Persistent_State
	util.load_json(&state, client.paths.persistent_state, mem.dynamic_arena_allocator(&arena))

	if state.theme != "" {
		theme: Theme
		if theme_load_from_name(client^, &theme, state.theme) {
			set_theme(client, theme, state.theme)
		}
	}

	set_background(client, state.background)

	client.enable_media_controls = state.enable_media_controls
	client.metadata_window.crop_art = state.crop_album_art
	client.analysis.spectrum_display_mode = state.analysis.spectrum_mode
	client.analysis.spectrum_bands = state.analysis.spectrum_bands
}*/
