#+private
package client

import "core:time"
import "core:slice"
import "core:strings"
//import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

import "src:server"

_Track_Table :: struct {
	track_id: server.Track_ID,
	metadata: Track_Metadata,
	track_index: int,
	tracks: []Track_ID,
	selection: ^_Selection,
	current_playing_track_id: Track_ID,
	playlist_id: Playlist_ID,
	_pos: int,
	_min: int,
	_max: int,
	_list_clipper: ^imgui.ListClipper,
}

_begin_track_table :: proc(
	str_id: cstring,
	playlist_id: Playlist_ID,
	current_playing_track_id: Track_ID,
	tracks: []Track_ID,
	selection: ^_Selection
) -> (table: _Track_Table, ok: bool) {
	table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_Hideable|
		imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Reorderable|imgui.TableFlags_RowBg|
		imgui.TableFlags_ScrollY

	column_flags := #partial [Metadata_Component]imgui.TableColumnFlags {
		.Title = {.NoHide},
		.Bitrate = {.DefaultHide},
		.Year = {.DefaultHide},
		.TrackNumber = {.DefaultHide},
		.Genre = {.DefaultHide},
		.DateAdded = {.DefaultHide},
	}

	if imgui.IsWindowFocused({.ChildWindows}) && _is_key_chord_pressed(.ImGuiMod_Ctrl, .A) {
		_selection_select_all(selection, playlist_id, tracks)
	}

	imgui.TextDisabled("%u tracks", u32(len(tracks)))

	if imgui.BeginTable(str_id, len(Metadata_Component), table_flags) {
		table.tracks = tracks
		table.selection = selection
		table.current_playing_track_id = current_playing_track_id
		table.playlist_id = playlist_id

		table._list_clipper = new(imgui.ListClipper)
		ok = true

		for component in Metadata_Component {
			imgui.TableSetupColumn(server.METADATA_COMPONENT_NAMES[component], column_flags[component])
		}

		imgui.TableSetupScrollFreeze(1, 1)
		imgui.TableHeadersRow()

		imgui.ListClipper_Begin(table._list_clipper, auto_cast len(table.tracks))

		return
	}

	return
}

_track_table_update_sort_spec :: proc(out_spec: ^server.Track_Sort_Spec) -> bool {
	sort_specs := imgui.TableGetSortSpecs()
	if sort_specs == nil {return false}

	if sort_specs.SpecsDirty {
		specs := sort_specs.Specs
		if specs == nil {
			out_spec.metric = .Album
			return false
		}
		
		out_spec.metric = cast(Metadata_Component) specs.ColumnIndex

		if specs.SortDirection == .Ascending {out_spec.order = .Ascending}
		else if specs.SortDirection == .Descending {out_spec.order = .Descending}

		sort_specs.SpecsDirty = false
		return true
	}

	return false
}

_track_table_row :: proc(cl: ^Client, lib: server.Library, it: ^_Track_Table) -> (not_done: bool) {
	if it._pos >= it._max {
		if !imgui.ListClipper_Step(it._list_clipper) {
			return false
		}

		it._min = int(it._list_clipper.DisplayStart)
		it._max = int(it._list_clipper.DisplayEnd)
		it._pos = it._min
	}
	
	imgui.TableNextRow()
	
	_string_column :: proc(track: ^Track_Metadata, component: Metadata_Component) {
		str := track.values[component].(string) or_else ""
		if str == "" {return}

		if imgui.TableSetColumnIndex(auto_cast component) {
			_native_text_unformatted(str)
		}
	}
	
	_number_column :: proc(track: Track_Metadata, component: Metadata_Component) {
		buf: [6]u8 = ---
		value := track.values[component].(i64) or_else 0
		if value == 0 {return}
		if imgui.TableSetColumnIndex(auto_cast component) {
			_native_textf(&buf, "%d", value)
		}
	}
	
	not_done = true
	it.track_index = it._pos
	it._pos += 1
	if it.track_index >= len(it.tracks) {return true}
	it.track_id = it.tracks[it.track_index]
	track_index, track_found := server.library_lookup_track(lib, it.track_id)
	if !track_found {return true}
	it.metadata = lib.track_metadata[track_index]
	track := it.metadata

	imgui.PushIDInt(auto_cast it.track_index)
	defer imgui.PopID()
	
	// Highlight track if it's playing
	if it.track_id == it.current_playing_track_id {
		imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(cl.theme.custom_colors[.PlayingHighlight]))
	}
	
	_number_column(track, .Year)
	_number_column(track, .TrackNumber)
	_string_column(&track, .Artist)
	_string_column(&track, .Album)
	_string_column(&track, .Genre)
	
	if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Duration) {
		buf: [12]u8
		h, m, s := time.clock_from_seconds(auto_cast (track.values[.Duration].(i64) or_else 0))
		_native_textf(&buf, "%02d:%02d:%02d", h, m, s)
	}

	if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Bitrate) {
		buf: [16]u8
		_native_text(&buf, track.values[.Bitrate].(i64) or_else 0, "kb/s")
	}

	if imgui.TableSetColumnIndex(auto_cast Metadata_Component.DateAdded) {
		buf: [16]u8
		ts := track.values[.DateAdded].(i64) or_else 0
		if ts != 0 {
			y, m, d := time.date(time.unix(ts, 0))
			_native_textf(&buf, "%04d/%02d/%02d", y, m, d)
		}
	}

	if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Title) {
		title := strings.unsafe_string_to_cstring(track.values[.Title].(string) or_else string(cstring("")))
		select: bool
		keep_selection: bool
		selected := it.selection.playlist_id == it.playlist_id && slice.contains(it.selection.tracks[:], it.track_id)

		select |= imgui.Selectable(title, selected, {.SpanAllColumns})
		if imgui.IsItemClicked(.Right) || imgui.IsItemClicked(.Middle) {
			keep_selection = true
			select = true
		}

		// Selection
		if select && it.selection != nil {
			shift := imgui.IsKeyDown(.ImGuiMod_Shift)
			ctrl := imgui.IsKeyDown(.ImGuiMod_Ctrl)

			if !ctrl && !shift && !(keep_selection && slice.contains(it.selection.tracks[:], it.track_id)) {
				_selection_clear(it.selection)
			}

			if shift {
				_selection_extend(it.selection, it.playlist_id, it.tracks, it.track_id)
			}
			else {
				_selection_add(it.selection, it.playlist_id, it.track_id)
			}
		}

		// Drag-drop
		if imgui.BeginDragDropSource() {
			_set_track_drag_drop_payload(cl, it.selection.tracks[:])
			imgui.EndDragDropSource()
		}
	}
	else {
		not_done = false
	}

	return
}

_end_track_table :: proc(table: _Track_Table) {
	imgui.ListClipper_End(table._list_clipper)
	free(table._list_clipper)
	imgui.EndTable()
}

_is_key_chord_pressed :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsKeyChordPressed(auto_cast(mods | key))
}

_play_track_input_pressed :: proc() -> bool {
	return imgui.IsItemClicked(.Middle) || (imgui.IsItemClicked(.Left) && imgui.IsMouseDoubleClicked(.Left))
}

_Track_Context_Menu_Result :: struct {
	add_to_playlist: Maybe(Playlist_ID),
}

_show_generic_track_context_menu_items :: proc(
	client: ^Client, sv: ^Server,
	track_id: Track_ID, md: Track_Metadata,
	result: ^_Track_Context_Menu_Result,
) {
	if imgui.BeginMenu("Add to playlist") {
		if len(sv.library.user_playlists.lists) == 0 {
			imgui.TextDisabled("No playlists")
		}

		for &playlist in sv.library.user_playlists.lists {
			if imgui.MenuItem(playlist.name) {
				result.add_to_playlist = playlist.id
			}
		}

		imgui.EndMenu()
	}

	if imgui.BeginMenu("Go to") {
		if imgui.MenuItem("Artist") {
			_go_to_artist(client, md)
		}
		if imgui.MenuItem("Album") {
			_go_to_album(client, md)
		}
		if imgui.MenuItem("Genre") {
			_go_to_genre(client, md)
		}
		imgui.EndMenu()
	}

	return
}

_process_track_context_menu_results :: proc(client: ^Client, sv: ^Server, result: _Track_Context_Menu_Result, tracks_arg: []Track_ID = nil) {
	tracks := tracks_arg != nil ? tracks_arg : client.selection.tracks[:]

	if result.add_to_playlist != nil {
		playlist_id := result.add_to_playlist.?
		playlist := server.library_get_playlist(sv.library, playlist_id)
		if playlist != nil {
			server.playlist_add_tracks(playlist, sv.library, tracks)
		}
	}
}
