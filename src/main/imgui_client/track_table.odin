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
#+private file
package client

import "src:main/player"
import "core:strings"
import "core:slice"
import "core:hash"
import "src:main/shared"
import "core:mem"
import "core:time"
import "core:fmt"
import lib "src:main/library"
import imgui "src:thirdparty/odin-imgui"
import "src:imx"

@private
Track_Table_Row :: struct {
	title:      string,
	url:        string,
	id:         lib.Track_ID,
	artists:    []lib.Artist_ID,
	genres:     []lib.Genre_ID,
	album:      Maybe(lib.Album_ID),
	format:     lib.Audio_File_Format,
	samplerate: [8]u8,
	duration:   [8]u8,
	year:       [4]u8,
	bitrate:    [9]u8,
	track_no:   [3]u8,
	selected:   bool,
}

@private
Track_Table :: struct {
	filter_buf:           [512]u8,
	filter_metrics:       bit_set[lib.Track_Filter_Metric],
	filter_hash:          u64,
	rows:                 []Track_Table_Row,
	rows_serial:          uint,
	playlist_uid:         shared.UID,
	sort_spec:            Maybe(lib.Track_Sort_Spec),
	scratch:              mem.Scratch,
	sort_spec_serial:     uint,
	sort_serial:          uint,
	show_filter_settings: bool,
	force_update:         bool,
	intialized:           bool,
}

@private Track_Table_Flag :: enum {NoRemove, IsQueue}
@private Track_Table_Flags :: bit_set[Track_Table_Flag]

_Column_Index :: enum {
	TrackNo,
	Title,
	Artist,
	Album,
	Genre,
	Duration,
	Bitrate,
	Format,
	Samplerate,
}

_FILTER_METRIC_NAMES := [lib.Track_Filter_Metric]cstring {
	.URL    = "URL/path",
	.Album  = "Album",
	.Artist = "Artist",
	.Genre  = "Genre",
	.Title  = "Title",
}

track_table_row_from_track :: proc(track_id: lib.Track_ID, allocator: mem.Allocator) -> (row: Track_Table_Row, ok: bool) {
	track := lib.get_track(track_id) or_return
	ok = true

	row.id      = track_id
	row.album   = track.album
	row.artists = track.artists
	row.genres  = track.genres
	row.title   = track.title
	row.url     = track.url

	{
		h, m, s := time.clock_from_seconds(auto_cast track.duration)
		fmt.bprintf(row.duration[:], "%02d:%02d:%02d", h, m, s)
	}

	if track.track != 0 do fmt.bprint(row.track_no[:], track.track)
	fmt.bprint(row.year[:], track.year)

	fmt.bprint(row.samplerate[:], track.samplerate, "Hz", sep="")
	fmt.bprint(row.bitrate[:], track.bitrate, "kb/s", sep="")
	row.format = track.format

	return
}

// track_table_update already checks this, but calling it manually
// can be used to avoid having to grab track ids from somewhere
@private
track_table_is_up_to_date :: proc(
	table:         ^Track_Table,
	tracks_serial: uint,
	playlist_uid:  shared.UID,
) -> bool {
	filter_hash := hash.fnv64a(transmute([]byte) string(cstring(&table.filter_buf[0])))

	up_to_date := table.intialized && !table.force_update && tracks_serial == table.rows_serial && 
		playlist_uid == table.playlist_uid &&
		filter_hash == table.filter_hash &&
		table.sort_serial == table.sort_spec_serial
	
	return up_to_date
}

@private
track_table_update :: proc(
	table:         ^Track_Table,
	tracks_serial: uint,
	track_ids_in:  []lib.Track_ID,
	playlist_uid:  shared.UID,
) {
	if !table.intialized {
		table.filter_metrics = ~{.URL}
		mem.scratch_init(&table.scratch, 64<<10)
	}
	
	filter_spec := lib.Track_Filter_Spec {
		text    = string(cstring(&table.filter_buf[0])),
		metrics = table.filter_metrics,
	}
	
	filter_hash := hash.fnv64a(transmute([]byte) filter_spec.text)

	if track_table_is_up_to_date(table, tracks_serial, playlist_uid) do return
	
	shared.TIME_SCOPE("Update track table of", len(track_ids_in))
	
	table.force_update = false
	table.intialized   = true
	table.rows_serial  = tracks_serial
	table.playlist_uid = playlist_uid
	table.filter_hash  = filter_hash
	table.sort_serial  = table.sort_spec_serial

	table.rows = nil

	mem.scratch_free_all(&table.scratch)
	allocator := mem.scratch_allocator(&table.scratch)

	track_ids := slice.clone(track_ids_in, get_frame_allocator())

	if table.filter_buf[0] != 0 {
		track_ids = lib.filter_tracks(track_ids, filter_spec)
	}

	if table.sort_spec != nil {
		lib.sort_track_ids(track_ids, table.sort_spec.?)
	}
	
	table.rows = make([]Track_Table_Row, len(track_ids), allocator)

	for track_id, i in track_ids {
		table.rows[i] = track_table_row_from_track(track_id, allocator) or_continue
	}
}

@private
track_table_show :: proc(
	table:         ^Track_Table,
	str_id:        cstring,
	flags:         Track_Table_Flags,
) -> bool {
	frame_allocator_guard()

	playback_state := get_last_playback_state()

	// --------------------------------------------------------------------------
	// Filter
	// --------------------------------------------------------------------------
	imgui.SetNextItemWidth(500)
	if is_key_chord_pressed_in_window(.ImGuiMod_Ctrl, .F) {
		imgui.SetKeyboardFocusHere()
	}
	imgui.InputTextWithHint("##filter", "Filter", cstring(&table.filter_buf[0]), auto_cast len(table.filter_buf))

	imgui.SameLine()
	if table.show_filter_settings {
		if imgui.Button("- Settings") do table.show_filter_settings = false

		imgui.Text("Filter by:")

		for metric in lib.Track_Filter_Metric {
			on := metric in table.filter_metrics

			imgui.SameLine()

			if imgui.Checkbox(_FILTER_METRIC_NAMES[metric], &on) {
				if on do table.filter_metrics |= {metric}
				else do table.filter_metrics &= ~{metric}

				table.force_update = true
			}
		}
	}
	else {
		if imgui.Button("+ Settings") do table.show_filter_settings = true
	}

	// --------------------------------------------------------------------------
	// Begin table
	// --------------------------------------------------------------------------
	imgui.TextDisabled("%d tracks", i32(len(table.rows)))

	if !playback_state.stopped && table.playlist_uid == player.get_current_playlist() {
		imgui.SameLine()
		imx.text_unformatted("- Now playing")
	}

	// Deferred events processed at the end of this proc
	actions: struct {
		play_track:             Maybe(lib.Track_ID),
		add_to_playlist:        Maybe(lib.Playlist_ID),
		play_selection:         bool,
		context_menu_target:    lib.Track_ID,
		play_similar_tracks:    bool,
		go_to_artist:           Maybe(lib.Artist_ID),
		go_to_album:            Maybe(lib.Album_ID),
		go_to_genre:            Maybe(lib.Genre_ID),
		add_selection_to_queue: bool,
	}

	list_clipper: imgui.ListClipper

	check_table_size() or_return

	// If true, scroll to the currently playing track if it's in this
	// table
	jump_to_playing := false

	// --------------------------------------------------------------------------
	// Control buttons
	// --------------------------------------------------------------------------
	if imgui.Button("Jump to current track") {
		jump_to_playing = true
	}

	// --------------------------------------------------------------------------
	// Hotkeys
	// --------------------------------------------------------------------------
	if is_key_chord_pressed_in_window(.ImGuiMod_Ctrl, .A) {
		for &row in table.rows {
			row.selected = true
		}
	}

	if is_key_chord_pressed(.ImGuiMod_Ctrl, .Space) {
		jump_to_playing = true
	}

	// --------------------------------------------------------------------------
	// Set up table
	// --------------------------------------------------------------------------
	imgui.BeginTable(str_id, auto_cast len(_Column_Index),
		imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Hideable|imgui.TableFlags_Reorderable|
		imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Sortable|
		imgui.TableFlags_ScrollX
	) or_return
	defer imgui.EndTable()

	// --------------------------------------------------------------------------
	// Columns
	// --------------------------------------------------------------------------
	column_infos: [_Column_Index]struct {
		name: cstring,
		sort_metric: lib.Track_Sort_Metric,
		flags: imgui.TableColumnFlags,
	} = {
		.Title =      {"Title",       .Title,      {.NoHide},    },
		.Artist =     {"Artist",      .Artist,     {},           },
		.Album =      {"Album",       .Album,      {},           },
		.Genre =      {"Genre",       .Genre,      {.DefaultHide}},
		.TrackNo =    {"Track",       .Track,      {.DefaultHide}},
		.Duration =   {"Duration",    .Duration,   {},           },
		.Bitrate =    {"Bitrate",     .Bitrate,    {.DefaultHide}},
		.Format =     {"Format",      .Format,     {.DefaultHide}},
		.Samplerate = {"Sample Rate", .Samplerate, {.DefaultHide}},
	}

	// --------------------------------------------------------------------------
	// Display table
	// --------------------------------------------------------------------------
	for col in column_infos {
		imgui.TableSetupColumn(col.name, col.flags, 1.0/f32(len(_Column_Index)))
	}

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	// --------------------------------------------------------------------------
	// Sort
	// --------------------------------------------------------------------------
	if table_sort_specs := imgui.TableGetSortSpecs(); table_sort_specs != nil {
		if specs := table_sort_specs.Specs; specs != nil && table_sort_specs.SpecsDirty {
			table_sort_specs.SpecsDirty = false

			column := cast(_Column_Index) specs.ColumnIndex
			switch specs.SortDirection {
			case .None:
				table.sort_spec = nil
			case .Ascending:
				table.sort_spec = lib.Track_Sort_Spec {
					metric = column_infos[column].sort_metric,
					order = .Ascending,
				}
			case .Descending:
				table.sort_spec = lib.Track_Sort_Spec {
					metric = column_infos[column].sort_metric,
					order = .Descending
				}
			}

			if table.sort_spec != nil {
				table.sort_spec_serial += 1
			}
		}
	}


	// --------------------------------------------------------------------------
	// Show rows
	// --------------------------------------------------------------------------
	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows), imgui.GetTextLineHeightWithSpacing())
	defer imgui.ListClipper_End(&list_clipper)

	// --------------------------------------------------------------------------
	// Jump to playing track
	// --------------------------------------------------------------------------
	if jump_to_playing && playback_state.track != nil {
		index := -1
		for row, i in table.rows {
			if row.id == playback_state.track.? {
				index = i
				break
			}
		}

		if index != -1 {
			imgui.ListClipper_IncludeItemByIndex(&list_clipper, auto_cast index)
		}
	}

	for imgui.ListClipper_Step(&list_clipper) {
		for &row, local_row_index in table.rows[list_clipper.DisplayStart:list_clipper.DisplayEnd] {
			imgui.TableNextRow()
			row_index := local_row_index + auto_cast list_clipper.DisplayStart
			imgui.PushIDInt(auto_cast row_index)
			defer imgui.PopID()

			if jump_to_playing && playback_state.track != nil {
				if row.id == playback_state.track.? {
					imgui.SetScrollHereY()
				}
			}	

			// --------------------------------------------------------------------
			// Title
			// --------------------------------------------------------------------
			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Title) {
				title_buf: [128]u8
				copy(title_buf[:127], row.title)

				if playback_state.track != nil && row.id == playback_state.track.? {
					imgui.TableSetBgColor(.RowBg0, get_theme_color(.PlayingHighlight))
				}

				if imgui.Selectable(cstring(&title_buf[0]), row.selected, {.SpanAllColumns}) {
					select_table_rows(table, row_index, false)
				}

				if imgui.BeginItemTooltip() {
					if track, got_track := lib.get_track(row.id); got_track {
						//_show_track_metadata_table(ui, "##metadata", sv^, track)
					}
					imgui.EndTooltip()
				}

				if imgui.IsItemClicked(.Middle) || imx.is_item_double_clicked() {
					actions.play_track = row.id
				}

				// -----------------------------------------------------------------
				// Context menu
				// -----------------------------------------------------------------
				if imgui.BeginPopupContextItem() {
					defer imgui.EndPopup()

					actions.context_menu_target = row.id

					select_table_rows(table, row_index, true)

					/*if add_to_playlist, yes := _show_playlist_selector_menu(sv, "Add to playlist"); yes {
						actions.add_to_playlist = add_to_playlist
					}*/

					if imgui.MenuItem("Play selection") {
						actions.play_selection = true
					}

					if imgui.MenuItem("Play similar tracks") {
						actions.play_similar_tracks = true
					}

					if imgui.MenuItem("Add to queue") {
						actions.add_selection_to_queue = true
					}

					imgui.Separator()
	
					if len(row.artists) != 0 && imgui.BeginMenu("More by...") {
						defer imgui.EndMenu()

						for a in row.artists {
							cs := strings.clone_to_cstring(lib.get_shared_string(.Artist, a), get_frame_allocator())
							if imgui.MenuItem(cs) {
								actions.go_to_artist = a
							}
						}
					}

					if row.album != 0 && imgui.MenuItem("View album") {
						actions.go_to_album = row.album
					}

					if imgui.BeginMenu("More in genre...") {
						defer imgui.EndMenu()

						for genre in row.genres {
							name := lib.get_shared_string(.Genre, genre)
							if imgui.MenuItem(strings.clone_to_cstring(name, get_frame_allocator())) {
								actions.go_to_genre = genre
							}
						}
					}


					if .NoRemove not_in flags {
						imgui.Separator()
						imgui.MenuItem("Remove")
					}
				}

			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Artist) {
				imx.text_unformatted(
					lib.join_shared_strings(.Artist, row.artists, get_frame_allocator())
				)
			}

			if row.album != nil && imgui.TableSetColumnIndex(auto_cast _Column_Index.Album) {
				imx.text_unformatted(lib.get_shared_string(.Album, row.album.?))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Genre) {
				imx.text_unformatted(
					lib.join_shared_strings(.Genre, row.genres, get_frame_allocator())
				)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Duration) {
				imx.text_unformatted(shared.string_from_array(row.duration[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.TrackNo) {
				imx.text_unformatted(shared.string_from_array(row.track_no[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Format) {
				imx.text_unformatted(lib.AUDIO_FILE_FORMAT_DISPLAY_NAMES[row.format].long)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Bitrate) {
				imx.text_unformatted(shared.string_from_array(row.bitrate[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Samplerate) {
				imx.text_unformatted(shared.string_from_array(row.samplerate[:]))
			}
		}
	}
	
	// --------------------------------------------------------------------------
	// Process actions
	// --------------------------------------------------------------------------
	if actions.play_track != nil {
		if .IsQueue in flags {
			player.play_track(actions.play_track.?)
		}
		else {
			tracks := track_table_get_tracks(table^, get_frame_allocator())
			player.play_playlist(tracks, table.playlist_uid, actions.play_track.?)
		}
	}

	if actions.play_selection {
		sel := track_table_get_selection(table^, get_frame_allocator())
		player.play_playlist(sel, table.playlist_uid)
	}

	if actions.add_to_playlist != nil {
		h := actions.add_to_playlist.?
		lib.add_to_playlist(h, track_table_get_selection(table^, get_frame_allocator()))
	}

	/*if actions.play_similar_tracks {
		server_request_radio(sv, actions.context_menu_target)
	}*/

	if actions.add_selection_to_queue {
		sel := track_table_get_selection(table^, get_frame_allocator())
		player.add_to_queue(sel, table.playlist_uid)
	}

	/*if actions.go_to_genre != nil do _go_to_genre(ui, actions.go_to_genre.?)
	if actions.go_to_album != nil do _go_to_album(ui, actions.go_to_album.?)
	if actions.go_to_artist != nil do _go_to_artist(ui, actions.go_to_artist.?)*/

	return true
}

track_table_get_tracks :: proc(t: Track_Table, allocator: mem.Allocator) -> []lib.Track_ID {
	out := make([]lib.Track_ID, len(t.rows), allocator)
	for row, i in t.rows {
		out[i] = row.id
	}

	return out
}

track_table_get_selection :: proc(t: Track_Table, allocator: mem.Allocator) -> []lib.Track_ID {
	out := make_dynamic_array([dynamic]lib.Track_ID, allocator)
	for row in t.rows {
		if row.selected do append(&out, row.id)
	}
	return out[:]
}
