#+private file
package main

import "core:mem"
import "core:container/handle_map"
import "src:imx"
import imgui "src:thirdparty/odin-imgui"
import "core:time"
import "core:fmt"

ICON_VOLUME_OFF :: ""
ICON_VOLUME_LOW :: ""
ICON_VOLUME_MEDIUM :: ""
ICON_VOLUME_HIGH :: ""
ICON_SHUFFLE :: ""
ICON_ARROW_RIGHT :: ""
ICON_PREVIOUS_TRACK :: ""
ICON_NEXT_TRACK :: ""
ICON_PAUSE :: ""
ICON_STOP :: ""
ICON_PLAY :: ""

_Theme_Color :: enum {
	PlayingHighlight,
}

_Track_Table_Row :: struct {
	album, artist, genre, title: string,
	duration: [9]u8,
	year: [4]u8,
	id: Track_ID,
	track_no: [3]u8,
	selected: bool,
}

_Track_Table :: struct {
	serial: uint,
	rows: [dynamic]_Track_Table_Row,
}

@private
UI :: struct {
	server: ^Server,
	windows: struct {
		library: struct {
			track_table: _Track_Table,
			tracks: []Track_ID,
			serial: uint,
		},

		queue: struct {
			serial: uint,
			track_table: _Track_Table,
		},
	},
	dialogs: struct {
		add_folder: File_Dialog_State,
	}
}

ui_theme: struct {
	colors: [_Theme_Color]u32,
	imgui_colors: [imgui.Col]u32,
}

@private
ui_init :: proc(ui: ^UI, server: ^Server) -> bool {
	ui.server = server

	style := imgui.GetStyle()
	style.FontSizeBase = 16

	it := handle_map.iterator_make(&server.tracks)
	for track, _ in handle_map.iterate(&it) {
		row := _track_table_row_from_track(server, track.handle) or_continue
		append(&ui.windows.library.track_table.rows, row)
	}

	add_font_from_memory :: proc(buf: []byte, merge: bool, scale_mod: f32 = 0) {
		font_buf := imgui.MemAlloc(len(buf))
		mem.copy(font_buf, raw_data(buf), len(buf))
		
		cfg := imgui.FontConfig {
			FontDataOwnedByAtlas = true,
			GlyphMaxAdvanceX = max(f32),
			RasterizerMultiply = 1,
			RasterizerDensity = 1,
			ExtraSizeScale = 1 + scale_mod,
			MergeMode = merge
		}

		io := imgui.GetIO()
		fonts := io.Fonts
		imgui.FontAtlas_AddFontFromMemoryTTF(fonts, font_buf, auto_cast len(buf), font_cfg = &cfg)
	}

	add_font_from_memory(#load("data/NotoSans-SemiBold.ttf"), false)
	add_font_from_memory(#load("data/Font Awesome 7 Free-Solid-900.otf"), true, -0.2)

	// Theme defaults
	ui_theme.colors[.PlayingHighlight] = 0xff0568fc

	return true
}

@private
ui_shutdown :: proc(ui: ^UI) {
}

@private
ui_show :: proc(ui: ^UI) {
	sv := ui.server

	imgui.PushStyleColor(.DockingEmptyBg, 0)
	imgui.PushStyleColor(.WindowBg, 0)
	imgui.DockSpaceOverViewport()
	imgui.PopStyleColor(2)

	// --------------------------------------------------------------------------
	// Folder dialog
	// --------------------------------------------------------------------------
	{
		results: [dynamic]Path
		defer delete(results)

		if async_file_dialog_get_results(&ui.dialogs.add_folder, &results) {
			for &p in results {
				server_queue_for_background_scan(sv, string(cstring(&p[0])))
			}
		}
	}

	// --------------------------------------------------------------------------
	// Main menu bar
	// --------------------------------------------------------------------------
	if imgui.BeginMainMenuBar() {
		defer imgui.EndMainMenuBar()

		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Add folders") {
				async_file_dialog_open(&ui.dialogs.add_folder, .Audio, {.SelectFolders, .SelectMultiple})
			}
			imgui.EndMenu()
		}

		// -----------------------------------------------------------------------
		// Volume
		// -----------------------------------------------------------------------
		imgui.Separator()
		volume := audio_get_volume() * 100
		volume_label: cstring = ICON_VOLUME_OFF + "###volume"

		if volume      >= 75 do volume_label = ICON_VOLUME_HIGH + "###volume"
		else if volume >= 50 do volume_label = ICON_VOLUME_MEDIUM + "###volume"
		else if volume >= 1 do volume_label = ICON_VOLUME_LOW + "###volume"

		imgui.SetNextItemWidth(100)
		if imgui.SliderFloat(volume_label, &volume, 0, 100, "%.0f%%") {
			audio_set_volume(volume / 100)
		}

		// -----------------------------------------------------------------------
		// Playback controls
		// -----------------------------------------------------------------------
		imgui.Separator()
		shuffled := server_is_shuffle_enabled(sv)

		if imgui.SmallButton(
			shuffled ? ICON_SHUFFLE + "###shuffle" : ICON_ARROW_RIGHT + "###shuffle"
		) {
			if shuffled {
				server_set_shuffle_enabled(sv, false)
			}
			else {
				server_set_shuffle_enabled(sv, true)
			}
		}

		if imgui.SmallButton(ICON_PREVIOUS_TRACK) {
			server_request_previous_track(sv)
		}

		imgui.BeginDisabled(sv.playback_state == .Stopped)
		
		switch sv.playback_state {
		case .Stopped, .Paused:
			if imgui.SmallButton(ICON_PLAY + "###playback_state") {
				server_request_resume(sv)
			}
		case .Playing:
			if imgui.SmallButton(ICON_PAUSE + "###playback_state") {
				server_request_pause(sv)
			}
		}
		imgui.EndDisabled()

		if imgui.SmallButton(ICON_NEXT_TRACK) {
			server_request_next_track(sv)
		}

		// -----------------------------------------------------------------------
		// Seek bar
		// -----------------------------------------------------------------------
		imgui.Separator()
		{
			current_pos := server_get_track_position_seconds(sv)
			duration := sv.track_info.duration

			dh, dm, ds := time.clock_from_seconds(auto_cast duration)
			ph, pm, ps := time.clock_from_seconds(auto_cast current_pos)
			imx.textf(32, "%02d:%02d:%02d/%02d:%02d:%02d", ph, pm, ps, dh, dm, ds)

			if imx.scrubber("##seekbar", &current_pos, 0, duration) {
				server_seek(sv, current_pos)
			}
		}
	}

	// --------------------------------------------------------------------------
	// Library
	// --------------------------------------------------------------------------
	if imgui.Begin("Library###library") {
		w := &ui.windows.library

		if w.serial != sv.tracks_serial {
			delete(w.tracks)
			w.serial = sv.tracks_serial
			w.tracks = server_get_all_tracks(sv, context.allocator)
		}

		_track_table_show(
			ui, "##library", &w.track_table, w.serial, w.tracks, {},
			0
		)
	}
	imgui.End()

	// --------------------------------------------------------------------------
	// Queue
	// --------------------------------------------------------------------------
	if imgui.Begin("Queue###queue") {
		w := &ui.windows.queue

		_track_table_show(
			ui, "##queue", &w.track_table, sv.playback.serial,
			server_get_queue(sv), {.IsQueue}, sv.queue_uid,
		)
	}
	imgui.End()
}

_track_table_row_from_track :: proc(
	sv: ^Server, handle: Track_ID
) -> (row: _Track_Table_Row, ok: bool) {
	track := get_track(sv, handle) or_return
	ok = true

	row.id = handle
	row.album = track.album
	row.artist = track.artist
	row.genre = track.genre
	row.title = track.title

	{
		h, m, s := time.clock_from_seconds(auto_cast track.duration_seconds)
		fmt.bprintf(row.duration[:], "%02d:%02d:%02d", h, m, s)
	}

	if row.track_no != 0 do fmt.bprint(row.track_no[:], track.track_no)
	fmt.bprint(row.year[:], track.release_year)

	return
}

_track_table_get_tracks :: proc(t: _Track_Table, allocator: mem.Allocator) -> []Track_ID {
	out := make([]Track_ID, len(t.rows), allocator)
	for row, i in t.rows {
		out[i] = row.id
	}

	return out
}

_Track_Table_Flag :: enum {IsQueue, NoRemove}

_track_table_show :: proc(
	ui: ^UI,
	name: cstring,
	table: ^_Track_Table,
	serial: uint,
	track_ids: []Track_ID,
	flags: bit_set[_Track_Table_Flag],
	playlist_id: UID,
) -> bool {

	select_row :: proc(table: ^_Track_Table, row_index: int) {
		if !imgui.IsKeyDown(.ImGuiMod_Ctrl) {
			for &row in table.rows do row.selected = false
		}
		table.rows[row_index].selected = true
	}

	// --------------------------------------------------------------------------
	// Update if needed
	// --------------------------------------------------------------------------
	if serial != table.serial {
		table.serial = serial
		clear(&table.rows)

		for track in track_ids {
			row := _track_table_row_from_track(ui.server, track) or_continue
			append(&table.rows, row)
		}
	}

	sv := ui.server

	// --------------------------------------------------------------------------
	// Show
	// --------------------------------------------------------------------------
	_Column_Index :: enum {
		TrackNo,
		Title,
		Artist,
		Album,
		Genre,
		Duration,
	}

	actions: struct {
		play_track: Maybe(Track_ID),
	}

	list_clipper: imgui.ListClipper

	imgui.BeginTable(name, auto_cast len(_Column_Index),
		imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Hideable|imgui.TableFlags_Reorderable|
		imgui.TableFlags_ScrollY|imgui.TableFlags_Resizable|
		imgui.TableFlags_SizingStretchProp|imgui.TableFlags_Sortable|
		imgui.TableFlags_SortTristate
	) or_return
	defer imgui.EndTable()

	column_infos: [_Column_Index]struct {
		flags: imgui.TableColumnFlags,
		name: cstring,
	} = {
		.Title = {name = "Title", flags = {.NoHide}},
		.Artist = {name = "Artist"},
		.Album = {name = "Album"},
		.Genre = {name = "Genre"},
		.TrackNo = {name = "Track"},
		.Duration = {name = "Duration"},
	}

	for col in column_infos {
		imgui.TableSetupColumn(col.name, col.flags, 1.0/f32(len(_Column_Index)))
	}

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows), imgui.GetTextLineHeight())

	for imgui.ListClipper_Step(&list_clipper) {
		for &row, local_row_index in table.rows[list_clipper.DisplayStart:list_clipper.DisplayEnd] {
			imgui.TableNextRow()
			row_index := local_row_index + auto_cast list_clipper.DisplayStart

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Title) {
				title_buf: [128]u8
				copy(title_buf[:127], row.title)

				if row.id == sv.current_track_id {
					imgui.TableSetBgColor(.RowBg0, ui_theme.colors[.PlayingHighlight])
				}

				if imgui.Selectable(cstring(&title_buf[0]), row.selected, {.SpanAllColumns}) {
					select_row(table, row_index)
				}

				if imgui.IsItemClicked(.Middle) {
					actions.play_track = row.id
				}

				if imgui.BeginPopupContextItem() {
					defer imgui.EndPopup()

					if .NoRemove not_in flags {
						imgui.Separator()
						imgui.MenuItem("Remove")
					}
				}
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Artist) {
				imx.text_unformatted(row.artist)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Album) {
				imx.text_unformatted(row.album)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Genre) {
				imx.text_unformatted(row.genre)
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.Duration) {
				imx.text_unformatted(string_from_array(row.duration[:]))
			}

			if imgui.TableSetColumnIndex(auto_cast _Column_Index.TrackNo) {
				imx.text_unformatted(string_from_array(row.track_no[:]))
			}
		}
	}
	
	if actions.play_track != nil {
		if .IsQueue in flags {
			server_move_queue_to_track(sv, actions.play_track.?)
		}
		else {
			tracks := _track_table_get_tracks(table^, context.allocator)
			defer delete(tracks)
			server_request_play_playlist(sv, tracks, playlist_id, actions.play_track.?)
		}
	}

	return true
}
