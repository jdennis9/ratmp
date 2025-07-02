#+private
package client

import "core:time"
import "core:slice"
import "core:strings"
import "core:fmt"
import "core:hash/xxhash"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:util"

_is_key_chord_pressed :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsKeyChordPressed(auto_cast(mods | key))
}

_play_track_input_pressed :: proc() -> bool {
	return imgui.IsItemClicked(.Middle) || (imgui.IsItemClicked(.Left) && imgui.IsMouseDoubleClicked(.Left))
}

_Track_Row :: struct {
	genre, artist, album: string,
	title: cstring,
	duration_str: [9]u8,
	duration_len: int,
	year_str: [4]u8,
	id: Track_ID,
	track_num, bitrate: i32,
	// @NOTE: Increase this to 5 characters in the 11th millenium
	date_added_str: [10]u8,
	selected: bool,
}

_Track_Table_Flag :: enum {NoSort,}
_Track_Table_Flags :: bit_set[_Track_Table_Flag]

_Track_Table_2 :: struct {
	rows: [dynamic]_Track_Row,
	serial: uint,
	playlist_id: Playlist_ID,
	filter_hash: u32,
	flags: _Track_Table_Flags,
	jump_to_track: Maybe(int),
}

_Track_Table_Result :: struct {
	play: Maybe(Track_ID),
	select: Maybe(Track_ID),
	context_menu: Maybe(Track_ID),
	selection_count: int,
	lowest_selection_index: int,
	sort_spec: Maybe(server.Track_Sort_Spec),
	play_selection: bool,
	add_selection_to_queue: bool,
}

_free_track_table :: proc(table: ^_Track_Table_2) {
	delete(table.rows)
	table.rows = nil
	table.serial = 0
}

_track_table_get_selection :: proc(table: _Track_Table_2, allocator := context.allocator) -> (ids: []Track_ID) {
	count := 0
	for row in table.rows {
		if row.selected {count += 1}
	}

	ids = make([]Track_ID, count, allocator)
	count = 0
	for row in table.rows {
		if row.selected {ids[count] = row.id; count += 1}
	}

	return
}

_track_table_get_tracks :: proc(table: _Track_Table_2, allocator := context.allocator) -> (ids: []Track_ID) {
	ids = make([]Track_ID, len(table.rows), allocator)
	for row, i in table.rows {
		ids[i] = row.id
	}
	return
}

_track_table_update :: proc(
	table: ^_Track_Table_2,
	serial: uint,
	lib: server.Library,
	tracks: []Track_ID,
	playlist_id: Playlist_ID,
	filter: string,
	flags: _Track_Table_Flags = {},
) {
	filter_hash := xxhash.XXH32(transmute([]u8) filter)
	table.flags = flags

	if len(table.rows) != 0 && table.serial == serial && table.playlist_id == playlist_id && table.filter_hash == filter_hash {return}
	table.playlist_id = playlist_id
	table.serial = serial
	table.filter_hash = filter_hash

	track_to_row :: proc(lib: server.Library, id: Track_ID) -> (row: _Track_Row, ok: bool) {
		md := server.library_get_track_metadata(lib, id) or_return

		row.id = id
		row.genre = md.values[.Genre].(string) or_else ""
		row.artist = md.values[.Artist].(string) or_else ""
		row.album = md.values[.Album].(string) or_else ""
		row.title = strings.unsafe_string_to_cstring(md.values[.Title].(string) or_else string(cstring("")))
		//row.year = auto_cast(md.values[.Year].(i64) or_else 0)
		row.track_num = auto_cast(md.values[.TrackNumber].(i64) or_else 0)
		row.bitrate = auto_cast(md.values[.Bitrate].(i64) or_else 0)

		duration := md.values[.Duration].(i64) or_else 0
		h, m, s := util.clock_from_seconds(auto_cast duration)
		row.duration_len = len(fmt.bprintf(row.duration_str[:], "%02d:%02d:%02d", h, m, s))
		fmt.bprintf(row.year_str[:], "%4d", md.values[.Year].(i64) or_else 0)

		year, month, day := time.date(time.unix(md.values[.DateAdded].(i64) or_else 0, 0))
		fmt.bprintf(row.date_added_str[:], "%4d-%2d-%2d", year, month, day)

		ok = true
		return
	}

	if filter == "" {
		clear(&table.rows)
		for track in tracks {
			row := track_to_row(lib, track) or_continue
			append(&table.rows, row)
		}
	}
	else {
		filtered: [dynamic]Track_ID
		defer delete(filtered)
		clear(&table.rows)
		spec := server.Track_Filter_Spec {
			components = ~{},
			filter = filter,
		}
		server.filter_tracks(lib, spec, tracks, &filtered)

		for track in filtered {
			row := track_to_row(lib, track) or_continue
			append(&table.rows, row)
		}
	}
}

_track_table_show :: proc(
	table: _Track_Table_2,
	str_id: cstring,
	theme: Theme,
	context_menu_id: imgui.ID,
	playing: Track_ID,
) -> (result: _Track_Table_Result) {
	list_clipper: imgui.ListClipper
	first_selected_row: Maybe(int)
	jump_to_track: Maybe(int)

	window_focused := imgui.IsWindowFocused({.ChildWindows})

	table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_Hideable|
		imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Reorderable|imgui.TableFlags_RowBg|
		imgui.TableFlags_ScrollY

	if .NoSort not_in table.flags {
		table_flags |= imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate
	}

	column_flags := #partial [Metadata_Component]imgui.TableColumnFlags {
		.Title = {.NoHide},
		.Bitrate = {.DefaultHide},
		.Year = {.DefaultHide},
		.TrackNumber = {.DefaultHide},
		.Genre = {.DefaultHide},
		.DateAdded = {.DefaultHide},
	}

	imgui.TextDisabled("%u tracks", u32(len(table.rows)))

	if !imgui.BeginTable(str_id, len(Metadata_Component), table_flags) {return}
	defer imgui.EndTable()

	for component in Metadata_Component {
		imgui.TableSetupColumn(server.METADATA_COMPONENT_NAMES[component], column_flags[component])
	}

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	// Sorting
	table_sort_specs := imgui.TableGetSortSpecs(); 
	if table_sort_specs != nil && table_sort_specs.Specs != nil && table_sort_specs.SpecsDirty {
		table_spec := table_sort_specs.Specs
		spec: server.Track_Sort_Spec
		spec.metric = auto_cast table_spec.ColumnIndex
		switch table_spec.SortDirection {
			case .Descending, .None: spec.order = .Descending
			case .Ascending: spec.order = .Ascending
		}

		table_sort_specs.SpecsDirty = false
		result.sort_spec = spec
	}

	// Handle hotkeys
	if window_focused {
		// Jump to track on Ctrl + Space
		if _is_key_chord_pressed(.ImGuiMod_Ctrl, .Space) {
			for row, index in table.rows {
				if row.id == playing {
					jump_to_track = index
					break
				}
			}
		}

		result.play_selection |= _is_key_chord_pressed(.ImGuiMod_Ctrl, .P)
		result.add_selection_to_queue |= _is_key_chord_pressed(.ImGuiMod_Ctrl, .Q)
	}

	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows))
	defer imgui.ListClipper_End(&list_clipper)

	if jump_to_track != nil {
		imgui.ListClipper_IncludeItemByIndex(&list_clipper, auto_cast jump_to_track.?)
	}

	for imgui.ListClipper_Step(&list_clipper) {
		for display_index in list_clipper.DisplayStart..<list_clipper.DisplayEnd {
			index := int(display_index)
			row := &table.rows[index]

			imgui.TableNextRow()

			if jump_to_track != nil && index == jump_to_track.? {
				imgui.SetScrollHereY()
			}
			
			if row.id == playing {
				imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(theme.custom_colors[.PlayingHighlight]))
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Artist) {
				_native_text_unformatted(row.artist)
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Album) {
				_native_text_unformatted(row.album)
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Genre) {
				_native_text_unformatted(row.genre)
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Duration) {
				_native_text_unformatted(string(row.duration_str[:row.duration_len]))
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Year) {
				_native_text_unformatted(string(row.year_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.DateAdded) {
				_native_text_unformatted(string(row.date_added_str[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Bitrate) {
				buf: [12]u8
				_native_text(&buf, row.bitrate, "kb/s")
			}

			if imgui.TableSetColumnIndex(auto_cast Metadata_Component.Title) {
				select: bool
				keep_selection: bool

				select |= imgui.Selectable(row.title, row.selected, {.SpanAllColumns})

				if _play_track_input_pressed() {
					result.play = row.id
					select = true
				}

				if imgui.IsItemClicked(.Right) {
					imgui.OpenPopupID(context_menu_id)
					result.context_menu = row.id
					select = true
					keep_selection = true
				}

				// Selection logic
				if select {
					ctrl := imgui.IsKeyDown(.ImGuiMod_Ctrl)
					shift := imgui.IsKeyDown(.ImGuiMod_Shift)

					result.select = row.id

					if !ctrl && !shift {
						if !keep_selection || !row.selected {for &r in table.rows {r.selected = false}}
						row.selected = true
					}
					else if (ctrl && shift) || shift {
						lo := max(int)
						hi := -1
						for r, i in table.rows {
							if r.selected {
								if i < index {lo = min(lo, i)}
								if i > index {hi = max(hi, i)}
							}
						}

						if lo == max(int) && hi == -1 {
							for &r in table.rows[0:index+1] {r.selected = true}
						} else if hi == -1 {
							for &r in table.rows[lo:index+1] {r.selected = true}
						} else if lo == max(int) {
							for &r in table.rows[index+1:hi] {r.selected = true}
						} else if ((hi-index) < (index-lo)) {
							for &r in table.rows[index:hi+1] {r.selected = true}
						} else {
							for &r in table.rows[lo:index+1] {r.selected = true}
						}
					}
					else if ctrl {
						row.selected = true
					}
				}

				if row.selected {
					first_selected_row = first_selected_row == nil ? int(index) : min(first_selected_row.?, int(index))
					result.lowest_selection_index = min(result.lowest_selection_index, index)
					result.selection_count += 1
				}
			}
		}
	}

	return
}

_Track_Table_Result_Process_Flag :: enum {
	// Tells proc to try set the queue position to a track when trying to play it, 
	// rather than queueing the entire playlist
	SetQueuePos,
}
_Track_Table_Result_Process_Flags :: bit_set[_Track_Table_Result_Process_Flag]

_track_table_process_results :: proc(
	table: _Track_Table_2, result: _Track_Table_Result,
	cl: ^Client, sv: ^Server, flags: _Track_Table_Result_Process_Flags,
) {
	if result.play != nil {
		if .SetQueuePos in flags {
			server.set_queue_track(sv, result.play.?)
		}
		else {
			tracks := _track_table_get_tracks(table)
			defer delete(tracks)
			server.play_playlist(sv, tracks, table.playlist_id, result.play.?)
		}
	}

	if result.play_selection {
		selection := _track_table_get_selection(table)
		defer delete(selection)
		server.play_playlist(sv, selection, table.playlist_id)
	}
	
	if result.add_selection_to_queue {
		selection := _track_table_get_selection(table)
		defer delete(selection)
		server.append_to_queue(sv, selection, table.playlist_id)
	}
}

_Track_Context_Flag :: enum {NoRemove, NoQueue}
_Track_Context_Flags :: bit_set[_Track_Context_Flag]
_Track_Context_Result :: struct {
	single_track: Maybe(Track_ID),
	go_to_album: bool,
	go_to_artist: bool,
	go_to_genre: bool,
	remove: bool,
	play: bool,
	add_to_queue: bool,
	add_to_playlist: Maybe(Playlist_ID),
}

_show_add_to_playlist_menu :: proc(sv: Server, result: ^_Track_Context_Result) {
	if imgui.BeginMenu("Add to playlist") {
		for playlist, i in sv.library.user_playlists.lists {
			if imgui.MenuItem(playlist.name) {
				result.add_to_playlist = sv.library.user_playlists.list_ids[i]
			}
		}
		imgui.EndMenu()
	}
}

_track_table_show_context :: proc(
	table: _Track_Table_2, table_result: _Track_Table_Result,
	context_id: imgui.ID, flags: _Track_Context_Flags, sv: Server,
) -> (result: _Track_Context_Result, shown: bool) #optional_ok {
	if table_result.selection_count == 0 {return}
	imgui.BeginPopupEx(context_id, {.AlwaysAutoResize} | imgui.WindowFlags_NoDecoration) or_return
	defer imgui.EndPopup()
	shown = true

	if table_result.selection_count == 1 {
		track_id := table.rows[table_result.lowest_selection_index].id
		result.single_track = track_id
		_track_show_context_items(track_id, &result, sv)
	}
	
	if .NoRemove not_in flags && imgui.MenuItem("Remove") {
		result.remove = true
	}

	if .NoQueue not_in flags {
		result.play |= imgui.MenuItem("Play", "Ctrl + P")
		result.add_to_queue |= imgui.MenuItem("Add to queue", "Ctrl + Q")
	}

	return
}

_track_show_context_items :: proc(
	track_id: Track_ID,
	result: ^_Track_Context_Result,
	sv: Server,
) {
	if imgui.BeginMenu("Go to") {
		if imgui.MenuItem("Album") {result.go_to_album = true}
		if imgui.MenuItem("Artist") {result.go_to_artist = true}
		if imgui.MenuItem("Genre") {result.go_to_genre = true}
		imgui.EndMenu()
	}
	_show_add_to_playlist_menu(sv, result)
}

_track_show_context :: proc(
	track_id: Track_ID,
	context_id: imgui.ID,
	sv: Server,
) -> (result: _Track_Context_Result) {
	result.single_track = track_id
	if imgui.BeginPopupEx(context_id, {.AlwaysAutoResize} | imgui.WindowFlags_NoDecoration) {
		_track_show_context_items(track_id, &result, sv)
		imgui.EndPopup()
	}
	return
}

_track_process_context :: proc(
	track_id: Track_ID,
	result: _Track_Context_Result,
	cl: ^Client,
	sv: ^Server,
	allow_add_to_playlist: bool,
) {
	if result.single_track != nil && (result.go_to_album || result.go_to_genre || result.go_to_artist) {
		md, found := server.library_get_track_metadata(sv.library, result.single_track.?)
		if found {
			if result.go_to_album {_go_to_album(cl, md)}
			if result.go_to_artist {_go_to_artist(cl, md)}
			if result.go_to_genre {_go_to_genre(cl, md)}
		}
	}

	if allow_add_to_playlist && result.add_to_playlist != nil {
		md, track_found := server.library_get_track_metadata(sv.library, track_id)
		playlist, playlist_found := server.playlist_list_get(sv.library.user_playlists, result.add_to_playlist.?)
		if track_found && playlist_found {
			server.playlist_add_track(playlist, track_id, md)
			sv.library.user_playlists.serial += 1
		}
	}
}

_track_table_process_context :: proc(
	table: _Track_Table_2, table_result: _Track_Table_Result,
	result: _Track_Context_Result, cl: ^Client, sv: ^Server,
) {
	if result.single_track != nil {
		_track_process_context(result.single_track.?, result, cl, sv, false)
	}
	else {
		if result.play {
			selection := _track_table_get_selection(table)
			defer delete(selection)
			server.play_playlist(sv, selection, table.playlist_id)
		}
		if result.add_to_queue {
			selection := _track_table_get_selection(table)
			defer delete(selection)
			server.append_to_queue(sv, selection, table.playlist_id)
		}
	}

	if result.add_to_playlist != nil {
		playlist, playlist_found := server.playlist_list_get(sv.library.user_playlists, result.add_to_playlist.?)
		if playlist_found {
			selection := _track_table_get_selection(table)
			defer delete(selection)
			server.playlist_add_tracks(playlist, sv.library, selection)
			sv.library.user_playlists.serial += 1
		}
	}
}
