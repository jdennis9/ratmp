#+private
package client

import imgui "src:thirdparty/odin-imgui"
import "core:slice"

import "src:server"

_Playlist_List_Window :: struct {
	selected_id: Playlist_ID,
	new_playlist_name: [128]u8,
}

_show_playlist_list_window :: proc(
	cl: ^Client, sv: ^Server,
	state: ^_Playlist_List_Window, cat: ^server.Playlist_List,
	allow_edit := false
) {
	root_table_flags := imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|
		imgui.TableFlags_BordersInner

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

		// Show playlist table
		if table, show_table := _begin_playlist_table("##groups", cat.lists[:], &state.selected_id); show_table {
			sort_spec: server.Playlist_Sort_Spec
			if _playlist_table_update_sort_spec(&sort_spec) {
				server.playlist_list_sort(cat^, sort_spec)
			}

			for _playlist_table_row(cl, &table, sv^) {
				// Play
				if _play_track_input_pressed() {
					server.play_playlist(sv, table.playlist.tracks[:], table.playlist.id)
					state.selected_id = table.playlist.id
				}

				// Right-click context
				if allow_edit && imgui.BeginPopupContextItem() {
					if imgui.MenuItem("Delete playlist") {
						want_delete_playlist = table.playlist.id
					}
					imgui.EndPopup()
				}

				if allow_edit && imgui.BeginDragDropTarget() {
					payload, have_payload := _get_track_drag_drop_payload(cl)
					if have_payload {
						server.playlist_add_tracks(table.playlist, sv.library, payload)
					}
					imgui.EndDragDropTarget()
				}
			}

			_end_playlist_table(&table)
		}
	}

	// Delete playlist
	if allow_edit && want_delete_playlist != nil {
		server.library_remove_playlist(&sv.library, want_delete_playlist.?)
	}

	// Tracks
	list_index, list_found := slice.linear_search(cat.list_ids[:], state.selected_id)

	// Show selected playlist tracks
	if list_found && imgui.TableSetColumnIndex(1) {
		context_menu: _Track_Context_Menu_Result
		defer _process_track_context_menu_results(cl, sv, context_menu, cl.selection.tracks[:])

		want_remove_selection := false
		list := &cat.lists[list_index]
		playlist_id := cat.list_ids[list_index]
		if table, show_table := _begin_track_table("##tracks", playlist_id, sv.current_track_id, list.tracks[:], &cl.selection); show_table {
			sort_spec: server.Track_Sort_Spec

			if _track_table_update_sort_spec(&sort_spec) {
				server.sort_tracks(sv.library, table.tracks[:], sort_spec)
			}

			for _track_table_row(cl, sv.library, &table) {
				if _play_track_input_pressed() {
					server.play_playlist(sv, table.tracks, playlist_id, table.track_id)
				}

				if imgui.BeginPopupContextItem() {
					_show_generic_track_context_menu_items(cl, sv, table.track_id, table.metadata, &context_menu)
					if allow_edit {
						imgui.Separator()
						if imgui.MenuItem("Remove") {
							want_remove_selection = true
						}
					}
					imgui.EndPopup()
				}
			}

			_end_track_table(table)
		}

		if allow_edit && want_remove_selection {
			server.playlist_remove_tracks(list, sv.library, cl.selection.tracks[:])
		}
	}
}
