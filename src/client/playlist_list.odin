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
#+private
package client

import "core:mem"
import "core:log"
import "core:strings"
import "core:container/small_array"
import imgui "src:thirdparty/odin-imgui"
import "core:slice"

import "src:server"

import "imx"

/*Auto_Playlist_Parameter_Editor :: struct {
	suggestions_allocator: mem.Allocator,
	suggestions_arena: mem.Dynamic_Arena,
	suggestions: [dynamic]cstring,
	suggestions_serial: uint,
	suggestion_index: int,
	ctor_index_of_suggestions: int,
	playlist_id: Global_Playlist_ID,
}

show_auto_playlist_parameter_editor :: proc(state: ^Auto_Playlist_Parameter_Editor, lib: ^Library, playlist: server.Playlist_Ptr) {
	playlist_constructor_type_is_choosable :: proc(t: server.Playlist_Auto_Build_Param_Type) -> bool {
		#partial switch t {
			case .Album: return true
			case .Artist: return true
			case .Genre: return true
		}

		return false
	}

	build_suggestions :: proc(state: ^Auto_Playlist_Parameter_Editor, lib: ^Library, playlist: server.Playlist_Ptr, ctor_index: int) {
		ap := &playlist.auto_build_params.?
		ctor := &ap.constructors.data[ctor_index]
		playlists_to_choose_from: ^server.Playlist_List

		log.debug("Build suggestions")

		
		clear(&state.suggestions)
		mem.dynamic_arena_free_all(&state.suggestions_arena)

		state.suggestion_index = 0
		state.suggestions_serial = lib.serial
		state.ctor_index_of_suggestions = ctor_index
		state.playlist_id = server.playlist_global_id(playlist)

		filter_lower := strings.to_lower(string(cstring(&ctor.arg[0])), context.temp_allocator)

		#partial switch ctor.type {
			case .Album: playlists_to_choose_from = &lib.categories.albums
			case .Artist: playlists_to_choose_from = &lib.categories.artists
			case .Genre: playlists_to_choose_from = &lib.categories.genres
		}

		if playlists_to_choose_from == nil {return}

		for pl in playlists_to_choose_from.playlists {
			if pl.name == "" {continue}

			name_lower := strings.to_lower(string(pl.name), context.temp_allocator)

			if strings.contains(name_lower, filter_lower) {
				append(&state.suggestions, strings.clone_to_cstring(pl.name, state.suggestions_allocator))
			}
		}
	}

	if state.suggestions_allocator.procedure == nil {
		mem.dynamic_arena_init(&state.suggestions_arena)
		state.suggestions_allocator = mem.dynamic_arena_allocator(&state.suggestions_arena)
	}

	ap := &playlist.auto_build_params.?
	edited: bool

	defer if edited {
		ap.build_serial = 0
		playlist.serial += 1
	}

	if state.playlist_id != server.playlist_global_id(playlist) || state.suggestions_serial != lib.serial {
		clear(&state.suggestions)
		state.suggestion_index = 0
	}

	for &ctor, ctor_index in small_array.slice(&ap.constructors) {
		focused: bool
		enum_name_buf: [64]u8

		imgui.PushIDPtr(&ctor)
		defer imgui.PopID()

		if imgui.BeginCombo("Type", enum_cstring(enum_name_buf[:], ctor.type)) {
			for t in server.Playlist_Auto_Build_Param_Type {
				if t == ctor.type {continue}
				if imgui.MenuItem(enum_cstring(enum_name_buf[:], t)) {
					ctor.type = t
					edited = true
				}
			}
			imgui.EndCombo()
		}

		choosable := playlist_constructor_type_is_choosable(ctor.type)

		if choosable {
			input_edited, input_focused := imx.input_text_with_suggestions("Filter", ctor.arg[:], state.suggestions[:], &state.suggestion_index)
			edited |= input_edited
			focused |= input_focused

			if edited || (input_focused && (ctor_index != state.ctor_index_of_suggestions || state.suggestions_serial != lib.serial)) {
				build_suggestions(state, lib, playlist, ctor_index)
			}
		}
		else if !choosable {
			edited |= imgui.InputText("Filter", cstring(&ctor.arg[0]), auto_cast len(ctor.arg))
		}

		imgui.Separator()
	}

	if imgui.Button("Add filter") {
		//server.playlist_add_auto_build_param(playlist)
		small_array.append(&ap.constructors)
	}
}

playlist_list_window_show :: proc(
	cl: ^Client, sv: ^Server,
	state: ^Playlists_Window, cat: ^server.Playlist_List,
	allow_edit := false
) {
	root_table_flags := imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|
		imgui.TableFlags_BordersInnerV

	if !imgui.BeginTable("##root", 2, root_table_flags) {return}
	defer imgui.EndTable()

	imgui.TableNextRow()

	want_delete_playlist: Maybe(Global_Playlist_ID)

	if imgui.TableSetColumnIndex(0) {
		// New playlist
		if allow_edit {
			commit := false
			auto_playlist := false
			name_cstring := cstring(&state.new_playlist_name[0])

			if imgui.InputTextWithHint("##new_playlist_name",
				"New playlist name", name_cstring,
				len(state.new_playlist_name), {.EnterReturnsTrue}
			) {
				commit |= true
			}
			imgui.SameLine()
			name_exists := server.playlist_list_name_exists(cat^, string(name_cstring))
			imgui.BeginDisabled(name_exists || name_cstring == "")
			commit |= imgui.Button("+ New playlist")
			imgui.SameLine()
			if imgui.Button("+ New Auto Playlist") {
				commit = true
				auto_playlist = true
			}
			imgui.EndDisabled()

			if commit && !name_exists {
				server.library_create_playlist(&sv.library, string(name_cstring), auto_playlist=auto_playlist)
				for &r in state.new_playlist_name {r = 0}
			}
		}

		context_id := imgui.GetID("##playlist_context_menu")
		filter_cstring := cstring(&state.playlist_filter[0])

		imgui.InputTextWithHint("##playlist_filter", "Filter", filter_cstring, auto_cast len(state.playlist_filter))
		playlist_table_update(&state.playlist_table, cat, string(filter_cstring), state.viewing_id, sv.current_playlist_id, state.editing_id)
		result := playlist_table_show(global_theme, state.playlist_table, "##playlists", context_id)

		if result.play != nil {
			playlist, _, found := server.playlist_list_find_playlist(cat, result.play.?)
			global_id := server.playlist_global_id(playlist)
			if found {
				server.play_playlist(sv, playlist.tracks[:], global_id)
				state.viewing_id = global_id
			}
		}
		if result.select != nil {
			state.viewing_id = Global_Playlist_ID{origin = cat.origin, id = result.select.?}
		}
		if result.sort_spec != nil {
			server.playlist_list_sort(cat, result.sort_spec.?)
		}
		if result.context_menu != nil {
			state.editing_id = Global_Playlist_ID{origin = cat.origin, id = result.context_menu.?}
		}

		if allow_edit && imgui.BeginPopupEx(context_id, imgui.WindowFlags_NoDecoration) {
			if imgui.MenuItem("Delete") {want_delete_playlist = state.editing_id}
			imgui.EndPopup()
		}
		else {state.editing_id = {}}
	}

	// Delete playlist
	if allow_edit && want_delete_playlist != nil {
		server.library_remove_playlist(&sv.library, want_delete_playlist.?)
	}

	// Tracks
	//list_index, list_found := slice.linear_search(cat.playlists[:], state.viewing_id)
	list_index, list_found := server.playlist_list_find_playlist_index(cat, state.viewing_id.id)

	// Show selected playlist tracks
	if list_found && imgui.TableSetColumnIndex(1) {
		list := &cat.playlists[list_index]
		context_menu_id := imgui.GetID("##track_context")
		filter_cstring := cstring(&state.track_filter[0])
		context_flags := allow_edit ? Track_Context_Flags{} : Track_Context_Flags{.NoRemove}

		// Edit auto playlist parameters
		if allow_edit && list.auto_build_params != nil {
			if imgui.CollapsingHeader("Auto Playlist Parameters") {
				show_auto_playlist_parameter_editor(&state.auto_playlist_param_editor, &sv.library, list)
			}
		}

		imgui.InputTextWithHint("##track_filter", "Filter", filter_cstring, auto_cast len(state.track_filter))
		track_table_update(&state.track_table, list.serial, sv.library, list.tracks[:], server.playlist_global_id(list), string(filter_cstring))
		result := track_table_show(state.track_table, "##tracks", context_menu_id, sv.current_track_id)

		track_table_process_result(state.track_table, result, cl, sv, {})
		if result.sort_spec != nil {
			server.playlist_sort(list, sv.library, result.sort_spec.?)
		}

		context_result := track_table_show_context(state.track_table, result, context_menu_id, context_flags, sv^)
		track_table_process_context(state.track_table, result, context_result, cl, sv)

		if allow_edit {
			if payload, have_payload := track_table_accept_drag_drop(result, context.allocator); have_payload {
				server.playlist_add_tracks(cat, sv.library, list_index, payload)
				delete(payload)
			}
		}

		if context_result.remove {
			selection := track_table_get_selection(state.track_table)
			defer delete(selection)
			server.playlist_remove_tracks(cat, sv.library, list_index, selection)
			cat.serial += 1
		}
	}
}

show_playlist_selector :: proc(name: cstring, from: server.Playlist_List) -> (id: Local_Playlist_ID, clicked: bool) {
	imgui.BeginMenu(name) or_return
	defer imgui.EndMenu()

	for pl, i in from.playlists {
		if pl.name_cstring != nil && imgui.MenuItem(pl.name_cstring) {
			id = pl.id
			clicked = true
		}
	}
	return
}
*/