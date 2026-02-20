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
#+private
package client

import "core:mem"
import "core:log"
import "core:strings"
import "core:container/small_array"
import imgui "src:thirdparty/odin-imgui"

import "src:server"

import "imx"

Auto_Playlist_Parameter_Editor :: struct {
	suggestions_allocator: mem.Allocator,
	suggestions_arena: mem.Dynamic_Arena,
	suggestions: [dynamic]cstring,
	suggestions_serial: uint,
	suggestion_index: int,
	param_index_of_suggestions: int,
	playlist_id: Playlist_ID,
}

show_auto_playlist_parameter_editor :: proc(state: ^Auto_Playlist_Parameter_Editor, lib: ^Library, playlist: ^Playlist) {
	
	playlist_constructor_type_is_choosable :: proc(t: server.Playlist_Auto_Build_Param_Type) -> bool {
		#partial switch t {
			case .Album: return true
			case .Artist: return true
			case .Genre: return true
		}
		
		return false
	}
	
	build_suggestions :: proc(state: ^Auto_Playlist_Parameter_Editor, lib: ^Library, playlist: ^Playlist, ctor_index: int) {
		ap := &playlist.auto_build_params.?
		ctor := &ap.params.data[ctor_index]
		playlists_to_choose_from: ^server.Track_Category
		
		log.debug("Build suggestions")
		
		clear(&state.suggestions)
		mem.dynamic_arena_free_all(&state.suggestions_arena)
		
		state.suggestion_index = 0
		state.suggestions_serial = lib.serial
		state.param_index_of_suggestions = ctor_index
		state.playlist_id = playlist.id
		
		filter_lower := strings.to_lower(string(cstring(&ctor.arg[0])), context.temp_allocator)
		
		#partial switch ctor.type {
			case .Album: playlists_to_choose_from = &lib.categories.albums
			case .Artist: playlists_to_choose_from = &lib.categories.artists
			case .Genre: playlists_to_choose_from = &lib.categories.genres
		}
		
		if playlists_to_choose_from == nil {return}
		
		for entry in playlists_to_choose_from.entries.name[:len(playlists_to_choose_from.entries)] {
			if entry == "" {continue}
			
			name_lower := strings.to_lower(string(entry), context.temp_allocator)
			
			if strings.contains(name_lower, filter_lower) {
				append(&state.suggestions, strings.clone_to_cstring(entry, state.suggestions_allocator))
			}
		}
	}
	
	if state.suggestions_allocator.procedure == nil {
		mem.dynamic_arena_init(&state.suggestions_arena)
		state.suggestions_allocator = mem.dynamic_arena_allocator(&state.suggestions_arena)
	}
	
	ap := &playlist.auto_build_params.?
	edited: bool
	want_remove_index: Maybe(int)
	
	defer if edited {
		ap.build_serial = 0
		playlist.serial += 1
	}
	
	if state.playlist_id != playlist.id || state.suggestions_serial != lib.serial {
		clear(&state.suggestions)
		state.suggestion_index = 0
	}
	
	
	for &param, param_index in small_array.slice(&ap.params) {
		focused: bool
		enum_name_buf: [64]u8

		imgui.PushIDPtr(&param)
		defer imgui.PopID()

		imgui.TextDisabled("%d tracks", i32(ap.track_count_by_constructor[param_index]))

		if imgui.BeginCombo("Type", enum_cstring(enum_name_buf[:], param.type)) {
			for t in server.Playlist_Auto_Build_Param_Type {
				if t == param.type {continue}
				if imgui.MenuItem(enum_cstring(enum_name_buf[:], t)) {
					param.type = t
					edited = true
				}
			}
			imgui.EndCombo()
		}

		choosable := playlist_constructor_type_is_choosable(param.type)

		if choosable {
			input_edited, input_focused := imx.input_text_with_suggestions("Filter", param.arg[:], state.suggestions[:], &state.suggestion_index)
			edited |= input_edited
			focused |= input_focused

			if edited || (input_focused && (param_index != state.param_index_of_suggestions || state.suggestions_serial != lib.serial)) {
				build_suggestions(state, lib, playlist, param_index)
			}
		}
		else if !choosable {
			edited |= imgui.InputText("Filter", cstring(&param.arg[0]), auto_cast len(param.arg))
		}

		if imgui.Button("Remove") {
			want_remove_index = param_index
		}

		imgui.Separator()
	}

	if want_remove_index != nil {
		small_array.ordered_remove(&ap.params, want_remove_index.?)
		server.playlist_mark_dirty(playlist, lib)
	}

	if imgui.Button("Add filter") {
		small_array.resize(&ap.params, small_array.len(ap.params)+1)
		server.playlist_mark_dirty(playlist, lib)
	}
}