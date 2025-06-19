#+private
package client

import "core:mem"

import "src:util"

@(private="file")
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
}

save_persistent_state :: proc(client: Client) {
	state: _Persistent_State

	state.theme = string(client.current_theme_name)
	state.background = client.background.path
	state.enable_media_controls = client.enable_media_controls
	state.crop_album_art = client.metadata_window.crop_art

	util.dump_json(state, client.paths.persistent_state)
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
}
