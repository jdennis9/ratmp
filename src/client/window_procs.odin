#+private
package client

import "core:container/small_array"
import "core:log"
import "base:runtime"
import imgui "src:thirdparty/odin-imgui"
import "imx"

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
		cl^, 
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
	window_bb := imx.get_window_bounding_box()

	track_table_update(cl^, &state.track_table, sv.queue_serial, sv.library, sv.queue[:], {origin = .Loose, id = max(u32)}, "", {.NoSort})
	table_result := track_table_show(state.track_table, "##queue", context_id, sv.current_track_id)

	//if table_result.sort_spec != nil {server.sort_queue(sv, table_result.sort_spec.?)}
	track_table_process_result(state.track_table, table_result, cl, sv, {.SetQueuePos})

	if payload, have_payload := track_table_accept_drag_drop("##queue_drag_drop", window_bb, context.allocator); have_payload {
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
	mode: Side_By_Side_Window_Mode,
	auto_playlist_param_editor: Auto_Playlist_Parameter_Editor,
	new_playlist_popup_id: imgui.ID,
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
	state.new_playlist_popup_id = imgui.GetID("##new_playlist")

	show_playlist_table :: proc(data: rawptr, cl: ^Client, sv: ^Server) {
		state := cast(^Playlists_Window) data
		imgui.PushID("##playlists")
		defer imgui.PopID()

		filter_cstring := cstring(&state.playlist_filter[0])
		commit_new_playlist := false
		auto_playlist := false

		imgui.InputTextWithHint("##filter", "Filter", filter_cstring, auto_cast len(state.playlist_filter))
		
		commit_new_playlist |= imgui.InputTextWithHint(
			"##playlist_name", "New playlist name", cstring(&state.new_playlist_name[0]),
			auto_cast len(state.new_playlist_name), {.EnterReturnsTrue}
		)
		
		new_playlist_name := string(cstring(&state.new_playlist_name[0]))
		new_playlist_name_exists := false
		for pl in sv.library.playlists {
			if pl.name == new_playlist_name {
				new_playlist_name_exists = true
				break
			}
		}

		imgui.BeginDisabled(new_playlist_name_exists || state.new_playlist_name[0] == 0)
		commit_new_playlist |= imgui.Button("+ New playlist")
		imgui.SameLine()
		if imgui.Button("+ New auto-playlist") {
			auto_playlist = true
			commit_new_playlist = true
		}
		imgui.EndDisabled()

		playlist_table_update(&state.playlist_table, sv.library.playlists[:], sv.library.playlists_serial, string(filter_cstring))
		result, _ := playlist_table_show(state.playlist_table, sv.library, state.viewing_id, state.editing_id, sv.current_playlist_id)

		if result.select != nil {
			state.viewing_id = result.select.?
		}

		if result.sort_spec != nil {
			server.library_sort_playlists(&sv.library, result.sort_spec.?)
		}

		if result.play != nil {
			if playlist, _, have_playlist := server.library_get_playlist(sv.library, result.play.?); have_playlist {
				server.play_playlist(sv, playlist.tracks[:], {.User, auto_cast playlist.id})
			}
		}

		if commit_new_playlist && !new_playlist_name_exists && new_playlist_name != "" {
			server.library_create_playlist(&sv.library, new_playlist_name, auto_playlist)
		}
	}

	show_track_table :: proc(data: rawptr, cl: ^Client, sv: ^Server) {
		state := cast(^Playlists_Window) data

		imgui.PushID("##tracks")
		defer imgui.PopID()

		playlist, _, have_playlist := server.library_get_playlist(sv.library, state.viewing_id)
		if !have_playlist {
			imgui.TextDisabled("No playlist selected")
			return
		}

		// =============================================================================
		// Auto-playlist parameters
		// =============================================================================

		if playlist.auto_build_params != nil && imgui.CollapsingHeader("Auto-playlist Parameters") {
			show_auto_playlist_parameter_editor(&state.auto_playlist_param_editor, &sv.library, playlist)
		}

		// =============================================================================
		// Track table
		// =============================================================================

		filter_cstring := cstring(&state.track_filter[0])

		imx.text_unformatted(playlist.name)

		imgui.InputTextWithHint("##filter", "Filter", filter_cstring, auto_cast len(state.track_filter))

		track_table_update(cl^, &state.track_table, playlist.serial, sv.library, playlist.tracks[:], {origin = .User, id = auto_cast playlist.id}, string(filter_cstring))

		context_menu_id := imgui.GetID("##track_context")
		table_result := track_table_show(state.track_table, "##track_table", context_menu_id, sv.current_track_id)
		context_result := track_table_show_context(state.track_table, table_result, context_menu_id, {}, sv^)

		track_table_process_result(state.track_table, table_result, cl, sv, {})
		track_table_process_context(state.track_table, table_result, context_result, cl, sv)

		if payload, have_payload := track_table_accept_drag_drop(
			"##playlist_drag_drop", imx.get_window_bounding_box(), context.allocator
		); have_payload {
			server.playlist_add_tracks(playlist, &sv.library, payload)
		}

		return
	}

	sbs := Side_By_Side_Window {
		left_proc = show_playlist_table,
		right_proc = show_track_table,
		mode = state.mode,
		focus_right = state.viewing_id != 0,
		data = state,
	}

	result := side_by_side_window_show(sbs, cl, sv)
	state.mode = result.mode
	if result.go_back do state.viewing_id = 0

	if imgui.BeginPopupEx(state.new_playlist_popup_id, {.AlwaysAutoResize}) {

		imgui.EndPopup()
	}
}

playlists_window_hide :: proc(self: ^Window_Base) {
	state := cast(^Playlists_Window) self
	playlist_table_free(&state.playlist_table)
}

// =============================================================================
// Artists, albums, genres
// =============================================================================

Track_Category_ID :: enum {
	Artists,
	Albums,
	Genres,
}

Track_Category_Window :: struct {
	using base: Window_Base,
	category_table: Track_Category_Table,
	track_table: Track_Table,
	mode: Side_By_Side_Window_Mode,
	viewing_hash: server.Track_Category_Hash,
	track_filter: [128]u8,
	category_filter: [128]u8,
	category: ^server.Track_Category,
}

track_category_window_set_view_by_name :: proc(window: ^Track_Category_Window, name: string) {
	hash := server.track_category_hash_string(name)
	window.viewing_hash = hash
	window.want_bring_to_front = true
}

ARTISTS_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Artists",
	internal_name = WINDOW_ARTIST,
	make_instance = track_category_window_make_instance,
	show = artists_window_show,
	hide = track_category_window_hide,
}

ALBUMS_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Albums",
	internal_name = WINDOW_ALBUMS,
	make_instance = track_category_window_make_instance,
	show = albums_window_show,
	hide = track_category_window_hide,
}

GENRES_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Genres",
	internal_name = WINDOW_GENRES,
	make_instance = track_category_window_make_instance,
	show = genres_window_show,
	hide = track_category_window_hide,
}

show_track_category_window :: proc(state: ^Track_Category_Window, cl: ^Client, sv: ^Server) {
	show_category_table :: proc(data: rawptr, cl: ^Client, sv: ^Server) {
		state := cast(^Track_Category_Window) data
		imgui.PushID("##categories")
		defer imgui.PopID()

		cat := state.category

		filter_cstring := cstring(&state.category_filter[0])

		imgui.InputTextWithHint("##filter", "Filter", filter_cstring, auto_cast len(state.category_filter))

		track_category_table_update(&state.category_table, cat, sv.library.categories.serial, string(filter_cstring))
		result, _ := track_category_table_show(state.category, state.category_table, sv.library, state.viewing_hash)

		if result.select != nil {
			state.viewing_hash = result.select.?
		}

		if result.sort_spec != nil {
			server.track_category_sort(&sv.library, cat, result.sort_spec.?)
		}

		if result.add_to_auto_playlist != nil {
			params := result.add_to_auto_playlist.?
			playlist, _, have_playlist := server.library_get_playlist(sv.library, params.playlist_id)
			entry_index, have_entry := server.track_category_find_entry_index(cat, params.hash)
			if have_playlist && have_entry {
				entry := &cat.entries[entry_index]
				server.playlist_add_auto_build_param(playlist, &sv.library, cat.auto_playlist_param_type, entry.name)
			}
		}

		if result.add_to_playlist != nil {
			params := result.add_to_playlist.?
			playlist, _, have_playlist := server.library_get_playlist(sv.library, params.playlist_id)
			entry_index, have_entry := server.track_category_find_entry_index(cat, params.hash)
			if have_playlist && have_entry {
				entry := &cat.entries[entry_index]
				server.playlist_add_tracks(playlist, &sv.library, entry.tracks[:])
			}
		}
		
		if result.play != nil {
			entry_index, have_entry := server.track_category_find_entry_index(cat, result.play.?)
			if have_entry {
				server.play_playlist(sv, cat.entries[entry_index].tracks[:], {
					server.track_property_to_playlist_origin(cat.from_property),
					auto_cast cat.entries[entry_index].hash
				})
			}
		}
	}

	show_track_table :: proc(data: rawptr, cl: ^Client, sv: ^Server) {
		state := cast(^Track_Category_Window) data

		imgui.PushID("##tracks")
		defer imgui.PopID()

		cat := state.category

		entry_index, have_entry := server.track_category_find_entry_index(cat, state.viewing_hash)
		if !have_entry {
			imgui.TextDisabled("No tracks")
			return
		}

		entry := &cat.entries[entry_index]

		filter_cstring := cstring(&state.track_filter[0])

		imx.text_unformatted(entry.name)

		imgui.InputTextWithHint("##filter", "Filter", filter_cstring, auto_cast len(state.category_filter))

		track_table_update(cl^, &state.track_table, sv.library.serial, sv.library, entry.tracks[:], {origin = .User, id = auto_cast entry.hash}, string(filter_cstring))

		context_menu_id := imgui.GetID("##track_context")
		table_result := track_table_show(state.track_table, "##track_table", context_menu_id, sv.current_track_id)
		context_result := track_table_show_context(state.track_table, table_result, context_menu_id, {.NoRemove}, sv^)

		track_table_process_result(state.track_table, table_result, cl, sv, {})
		track_table_process_context(state.track_table, table_result, context_result, cl, sv)

		return
	}

	sbs := Side_By_Side_Window {
		left_proc = show_category_table,
		right_proc = show_track_table,
		mode = state.mode,
		focus_right = state.viewing_hash != 0,
		data = state,
	}

	result := side_by_side_window_show(sbs, cl, sv)
	state.mode = result.mode
	if result.go_back {
		state.viewing_hash = 0
	}
}

track_category_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Track_Category_Window, allocator)
}

track_category_window_hide :: proc(self: ^Window_Base) {
	state := cast(^Track_Category_Window) self
	track_table_free(&state.track_table)
	track_category_table_free(&state.category_table)
}

artists_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Track_Category_Window) self
	state.category = &sv.library.categories.artists
	show_track_category_window(state, cl, sv)
}

albums_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Track_Category_Window) self
	state.category = &sv.library.categories.albums
	show_track_category_window(state, cl, sv)
}


genres_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Track_Category_Window) self
	state.category = &sv.library.categories.genres
	show_track_category_window(state, cl, sv)
}

