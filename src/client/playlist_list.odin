#+private
package client

import imgui "src:thirdparty/odin-imgui"
import "core:slice"

import "src:server"

_Playlist_List_Window :: struct {
	viewing_id: Playlist_ID,
	editing_id: Playlist_ID,
	new_playlist_name: [128]u8,
	playlist_table: _Playlist_Table_2,
	track_table: _Track_Table_2,
	track_filter: [128]u8,
	playlist_filter: [128]u8,
}

_show_playlist_list_window :: proc(
	cl: ^Client, sv: ^Server,
	state: ^_Playlist_List_Window, cat: ^server.Playlist_List,
	allow_edit := false
) {
	root_table_flags := imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|
		imgui.TableFlags_BordersInnerV

	if !imgui.BeginTable("##root", 2, root_table_flags) {return}
	defer imgui.EndTable()

	imgui.TableNextRow()

	want_delete_playlist: Maybe(Playlist_ID)

	if imgui.TableSetColumnIndex(0) {
		// New playlist
		if allow_edit {
			commit := false
			name_cstring := cstring(&state.new_playlist_name[0])

			if imgui.InputTextWithHint("##new_playlist_name",
				"New playlist name", name_cstring,
				len(state.new_playlist_name), {.EnterReturnsTrue}
			) {
				commit |= true
			}
			imgui.SameLine()
			name_exists := server.playlist_list_name_exists(cat, string(name_cstring))
			imgui.BeginDisabled(name_exists || name_cstring == "")
			commit |= imgui.Button("+ New playlist")
			imgui.EndDisabled()

			if commit && !name_exists {
				server.library_create_playlist(&sv.library, string(name_cstring))
				for &r in state.new_playlist_name {r = 0}
			}
		}

		context_id := imgui.GetID("##playlist_context_menu")
		filter_cstring := cstring(&state.playlist_filter[0])

		imgui.InputTextWithHint("##playlist_filter", "Filter", filter_cstring, auto_cast len(state.playlist_filter))
		_update_playlist_table(&state.playlist_table, cat, string(filter_cstring), state.viewing_id, sv.current_playlist_id, state.editing_id)
		result := _display_playlist_table(cl.theme, state.playlist_table, "##playlists", context_id)

		if result.play != nil {
			playlist, found := server.playlist_list_get(cat^, result.play.?)
			if found {
				server.play_playlist(sv, playlist.tracks[:], playlist.id)
				state.viewing_id = playlist.id
			}
		}
		if result.select != nil {state.viewing_id = result.select.?}
		if result.sort_spec != nil {server.playlist_list_sort(cat, result.sort_spec.?)}
		if result.context_menu != nil {state.editing_id = result.context_menu.?}

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
	list_index, list_found := slice.linear_search(cat.list_ids[:], state.viewing_id)

	// Show selected playlist tracks
	if list_found && imgui.TableSetColumnIndex(1) {
		list := &cat.lists[list_index]
		context_menu_id := imgui.GetID("##track_context")
		filter_cstring := cstring(&state.track_filter[0])
		context_flags := allow_edit ? _Track_Context_Flags{} : _Track_Context_Flags{.NoRemove}

		imgui.InputTextWithHint("##track_filter", "Filter", filter_cstring, auto_cast len(state.track_filter))
		_track_table_update(&state.track_table, list.serial, sv.library, list.tracks[:], list.id, string(filter_cstring))
		result := _track_table_show(state.track_table, "##tracks", cl.theme, context_menu_id, sv.current_track_id)

		_track_table_process_results(state.track_table, result, cl, sv, {})
		if result.sort_spec != nil {server.playlist_sort(list, sv.library, result.sort_spec.?)}

		context_result := _track_table_show_context(state.track_table, result, context_menu_id, context_flags, sv^)
		_track_table_process_context(state.track_table, result, context_result, cl, sv)

		if context_result.remove {
			selection := _track_table_get_selection(state.track_table)
			defer delete(selection)
			server.playlist_remove_tracks(list, sv.library, selection)
			cat.serial += 1
		}
	}
}

_show_playlist_selector :: proc(name: cstring, from: server.Playlist_List) -> (id: Playlist_ID, clicked: bool) {
	imgui.BeginMenu(name) or_return
	defer imgui.EndMenu()

	for pl, i in from.lists {
		if pl.name != nil && imgui.MenuItem(pl.name) {
			id = from.list_ids[i]
			clicked = true
		}
	}
	return
}
