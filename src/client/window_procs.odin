#+private
package client

import "base:runtime"
import imgui "src:thirdparty/odin-imgui"

import "src:server"

// =============================================================================
// Library
// =============================================================================

Library_Window :: struct {
	using base: Window_Base,
	filter: [512]u8,
	track_table: Track_Table,
}

LIBRARY_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Library",
	internal_name = WINDOW_LIBRARY,
	make_instance = library_window_make_instance,
	show = library_window_show,
	hide = library_window_hide,
	flags = {.DefaultShow},
}

library_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Library_Window, allocator)
}

library_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Library_Window) self
	filter_cstring := cstring(&state.filter[0])
	context_id := imgui.GetID("##library_track_context")

	imgui.InputTextWithHint("##library_filter", "Filter", filter_cstring, auto_cast len(state.filter))

	track_table_update(
		&state.track_table, sv.library.serial, sv.library,
		server.library_get_all_track_ids(sv.library), {}, string(filter_cstring)
	)
	table_result := track_table_show(
		state.track_table, "##library_table", context_id, sv.current_track_id
	)

	if table_result.sort_spec != nil {server.library_sort(&sv.library, table_result.sort_spec.?)}
	track_table_process_result(state.track_table, table_result, cl, sv, {})

	context_result := track_table_show_context(state.track_table, table_result, context_id, {}, sv^)
	track_table_process_context(state.track_table, table_result, context_result, cl, sv)

	if context_result.remove {
		selection := track_table_get_selection(state.track_table)
		defer delete(selection)
		for track in selection {
			server.library_remove_track(&sv.library, track)
		}
	}
}

library_window_hide :: proc(self: ^Window_Base) {
	state := cast(^Library_Window) self
	track_table_free(&state.track_table)
}

// =============================================================================
// Queue
// =============================================================================

Queue_Window :: struct {
	using base: Window_Base,
	filter: [512]u8,
	track_table: Track_Table,
}

QUEUE_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Queue",
	internal_name = WINDOW_QUEUE,
	make_instance = queue_window_make_instance,
	show = queue_window_show,
	hide = queue_window_hide,
	flags = {.DefaultShow},
}

queue_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	r := new(Queue_Window, allocator)
	return r
}

queue_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Queue_Window) self
	context_id := imgui.GetID("##track_context")

	track_table_update(&state.track_table, sv.queue_serial, sv.library, sv.queue[:], {serial=max(u32)}, "", {.NoSort})
	table_result := track_table_show(state.track_table, "##queue", context_id, sv.current_track_id)

	//if table_result.sort_spec != nil {server.sort_queue(sv, table_result.sort_spec.?)}
	track_table_process_result(state.track_table, table_result, cl, sv, {.SetQueuePos})

	if payload, have_payload := track_table_accept_drag_drop(table_result, context.allocator); have_payload {
		server.append_to_queue(sv, payload, {})
		delete(payload)
	}
	
	context_result := track_table_show_context(state.track_table, table_result, context_id, {}, sv^)
	track_table_process_context(state.track_table, table_result, context_result, cl, sv)

	if context_result.remove {
		selection := track_table_get_selection(state.track_table)
		defer delete(selection)
		server.remove_tracks_from_queue(sv, selection)
	}
}

queue_window_hide :: proc(self: ^Window_Base) {
	state := cast(^Queue_Window) self
	track_table_free(&state.track_table)
}

// =============================================================================
// Playlists
// =============================================================================

Playlists_Window :: struct {
	using base: Window_Base,
	playlist_table: Playlist_Table,
	viewing_id: Playlist_ID,
	editing_id: Playlist_ID,
	new_playlist_name: [128]u8,
	track_table: Track_Table,
	track_filter: [128]u8,
	playlist_filter: [128]u8,
}

PLAYLISTS_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Playlists",
	internal_name = WINDOW_PLAYLISTS,
	make_instance = playlists_window_make_instance,
	show = playlists_window_show,
	hide = playlists_window_hide,
	flags = {.MultiInstance, .DefaultShow},
}

playlists_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Playlists_Window, allocator)
}

playlists_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Playlists_Window) self
	playlist_list_window_show(cl, sv, state, &sv.library.user_playlists, allow_edit = true)
}

playlists_window_hide :: proc(self: ^Window_Base) {
	state := cast(^Playlists_Window) self
	playlist_table_free(&state.playlist_table)
}

// =============================================================================
// Artists, albums, genres
// =============================================================================

playlists_window_set_view_by_name :: proc(window: ^Playlists_Window, name: string, component: Metadata_Component) {
	id := server.library_hash_string(name)
	window.viewing_id = {serial=auto_cast component, pool=id}
	window.want_bring_to_front = true
}

ARTISTS_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Artists",
	internal_name = WINDOW_ARTIST,
	make_instance = playlists_window_make_instance,
	show = artists_window_show,
	hide = playlists_window_hide,
}

ALBUMS_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Albums",
	internal_name = WINDOW_ALBUMS,
	make_instance = playlists_window_make_instance,
	show = albums_window_show,
	hide = playlists_window_hide,
}

GENRES_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Genres",
	internal_name = WINDOW_GENRES,
	make_instance = playlists_window_make_instance,
	show = genres_window_show,
	hide = playlists_window_hide,
}

artists_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Playlists_Window) self
	playlist_list_window_show(cl, sv, state, &sv.library.categories.artists)
}

albums_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Playlists_Window) self
	playlist_list_window_show(cl, sv, state, &sv.library.categories.albums)
}

genres_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Playlists_Window) self
	playlist_list_window_show(cl, sv, state, &sv.library.categories.genres)
}

