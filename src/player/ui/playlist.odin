/*
	RAT MP: A lightweight graphical music player
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
package ui

import "core:slice"
import "core:time"

import imgui "../../libs/odin-imgui"

import "player:library"
import "player:theme"

Track_Table_Flag :: enum {
	NoRemove,
	//IsQueue,
	NoAddToQueue,
	NoFilter,
	NoSort,
}

Track_Table_Flags :: bit_set[Track_Table_Flag]

Playlist_Filter :: struct {
	text: string,
}

@(private="file")
Track_Column :: enum {
	Artist,
	Album,
	Title,
	Duration,
	Genre,
}

@(private="file")
Column :: struct {
	name: cstring,
	sort_metric: library.Track_Sort_Metric,
	flags: imgui.TableColumnFlags,
}

@private
_get_track_column_sort_metric :: proc(index: int) -> library.Track_Sort_Metric {
	col := cast(Track_Column)index

	switch col {
		case .Album: return .Album
		case .Artist: return .Artist
		case .Title: return .Title
		case .Genre: return .Genre
		case .Duration: return .Duration
	}

	return .None
}

_show_track_playlist_context_menu :: proc(track: library.Track_ID, action: ^Track_Table_Action, flags: Track_Table_Flags) {
	if (.NoAddToQueue not_in flags) && imgui.MenuItem("Add to queue") {
		action.add_to_queue |= true
	}
}

/*@(private="file")
_show_track_row :: proc(
	action: ^Track_Table_Action, playlist: lib.Playlist, track_index: int, selected: bool, 
	have_filter: bool, jump_to_playing: bool, flags: Track_Table_Flags
) {
	track_id := playlist.tracks[track_index];
	selected := _is_track_selected(track_id);
	track := lib.get_track_info(track_id);

	imgui.PushIDInt(auto_cast track_index);
	defer imgui.PopID();
	imgui.TableNextRow();
	playing_track := playback.get_playing_track();
	
	if track_id == playing_track {
		imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(theme.custom_colors[.PlayingHighlight]));

		if jump_to_playing {imgui.SetScrollHereY()}
	}

	if imgui.TableSetColumnIndex(cast(i32) Column_Index.Title) {
		clicked := imgui.Selectable(track.title, selected, {.SpanAllColumns});

		if clicked {
			action.select_track = track_index;
		}

		if imgui.IsItemClicked(.Middle) {
			action.play_track = track_index;
		}

		if imgui.IsMouseDoubleClicked(.Left) && imgui.IsItemHovered() {
			action.play_track = track_index;
		}

		// ---------------------------------------------------------------------
		// Drag-drop
		// ---------------------------------------------------------------------
		if imgui.BeginDragDropSource() {
			//action.select_track = track_index;
			//imgui.SetDragDropPayload("selection", nil, 0);
			tracks := _get_selected_tracks_in_playlist(playlist);
			defer delete(tracks);
			_set_track_drag_drop_payload(tracks);
			imgui.SetTooltip("%d tracks", cast(i32) len(tracks));
			imgui.EndDragDropSource();
		}

		// -----------------------------------------------------------------
		// Context menu
		// -----------------------------------------------------------------
		if imgui.BeginPopupContextItem() {
			action.select_track = track_index;

			_show_track_base_context_menu(playlist.id, track_id);
			if .NoAddToQueue not_in flags {
				imgui.Separator();
				_show_track_playlist_context_menu(track_id, action, flags);
			}

			if .NoRemove not_in flags {
				imgui.Separator();
				action.remove |= imgui.MenuItem("Remove");
			}

			imgui.EndPopup();
		}

	}


	if imgui.TableSetColumnIndex(cast(i32) Column_Index.Genre) {
		imgui.TextUnformatted(track.genre);
	}

	if imgui.TableSetColumnIndex(cast(i32) Column_Index.Duration) {
		hours, minutes, seconds := util.split_seconds(cast(i32) track.duration_seconds);
		imgui.Text("%02d:%02d:%02d", hours, minutes, seconds);
	}

	if imgui.TableSetColumnIndex(cast(i32) Column_Index.Artist) {
		imgui.TextUnformatted(track.artist);
	}

	if imgui.TableSetColumnIndex(cast(i32) Column_Index.Album) {
		imgui.TextUnformatted(track.album);
	}

	return;
}*/

@(private="file")
_force_track_in_list_clipper :: proc(clipper: ^imgui.ListClipper, tracks: []library.Track_ID, track: library.Track_ID, use_filter: bool) {
	index, found := slice.linear_search(tracks[:], track)

	if !found {return}
	imgui.ListClipper_ForceDisplayRangeByIndices(clipper, cast(i32) index, cast(i32) index + 1)
}

Playlist_Sort_Spec :: struct {
	metric: library.Track_Sort_Metric,
	order: library.Sort_Order,
}

Track_Table_Action :: struct {
	select_track: Maybe(int),
	play_track: Maybe(int),
	sort_spec: Maybe(Playlist_Sort_Spec),
	drag_drop_payload: []library.Track_ID,
	play_selection: bool,
	select_all: bool,
	add_selection_to_playlist: bool,
	drop_files: bool,
	remove: bool,
	add_to_queue: bool,

	filter: string,
	filter_hash: u32,
}

_set_track_drag_drop_payload :: proc(tracks: []library.Track_ID) {
	imgui.SetDragDropPayload("tracks", raw_data(tracks), size_of(library.Track_ID) * len(tracks))
}

_Track_Table_Iterator :: struct {
	tracks: []library.Track_ID,
	selection: []library.Track_ID,
	track: library.Track_ID,
	track_index: int,
	// True if the selectable column is visible
	visible: bool,

	_list_clipper: ^imgui.ListClipper,
	_pos: int,
	_min, _max: int,
}

_begin_track_table :: proc(
	lib: Library, str_id: cstring, tracks: []Track_ID, playlist_id: Playlist_ID, selection: ^_Selection
) -> (iterator: _Track_Table_Iterator, begin: bool) {
	table_flags := 
	imgui.TableFlags_Resizable|imgui.TableFlags_Hideable|
	imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
	imgui.TableFlags_Reorderable|imgui.TableFlags_ScrollY|
	imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate

	columns := [Track_Column]Column {
		.Artist = {name = "Artist", sort_metric = .Artist},
		.Album = {name = "Album", sort_metric = .Album},
		.Title = {name = "Title", flags = {.NoHide}, sort_metric = .Title},
		.Genre = {name = "Genre", flags = {.DefaultHide}, sort_metric = .Genre},
		.Duration = {name = "Duration", sort_metric = .Duration},
	}

	
	if imgui.IsWindowFocused({.ChildWindows}) && _is_key_chord_pressed(.ImGuiMod_Ctrl, imgui.Key.A) {
		selection.playlist_id = playlist_id
		resize(&selection.tracks, len(tracks[:]))
		copy(selection.tracks[:], tracks[:])
	}
	
	iterator.tracks = tracks
	iterator.selection = selection.playlist_id == playlist_id ? selection.tracks[:] : nil
	iterator._list_clipper = new(imgui.ListClipper)

	if imgui.BeginTable(str_id, auto_cast len(Track_Column), table_flags) {
		for col in columns {imgui.TableSetupColumn(col.name, col.flags)}
		imgui.TableSetupScrollFreeze(1, 1)
		imgui.TableHeadersRow()
		imgui.ListClipper_Begin(iterator._list_clipper, auto_cast len(iterator.tracks), imgui.GetTextLineHeightWithSpacing())
		begin = true
		return
	}

	return
}

// Call right after _begin_track_table returns true
_track_table_update_sort_spec :: proc(spec: ^library.Track_Sort_Spec) -> bool {
	sort_specs := imgui.TableGetSortSpecs()
	if sort_specs == nil {return false}

	if sort_specs.SpecsDirty {
		specs := sort_specs.Specs
		if specs == nil {
			spec.metric = .None
			return true
		}
		
		spec.metric = _get_track_column_sort_metric(auto_cast specs.ColumnIndex)
		if specs.SortDirection == .Ascending {spec.order = .Ascending}
		else if specs.SortDirection == .Descending {spec.order = .Descending}

		sort_specs.SpecsDirty = false
		return true
	}

	return false
}

_show_next_track_table_row :: proc(lib: library.Library, pb: Playback, it: ^_Track_Table_Iterator) -> bool {
	if it._pos >= it._max {
		if !imgui.ListClipper_Step(it._list_clipper) {
			return false
		}

		it._min = int(it._list_clipper.DisplayStart)
		it._max = int(it._list_clipper.DisplayEnd)
		it._pos = it._min
	}

	imgui.TableNextRow()

	it.visible = false
	it.track_index = it._pos
	it.track = it.tracks[it._pos]
	track := library.get_track_info(lib, it.track)
	it._pos += 1

	if imgui.TableSetColumnIndex(auto_cast Track_Column.Album) {imgui.TextUnformatted(track.album)}
	if imgui.TableSetColumnIndex(auto_cast Track_Column.Artist) {imgui.TextUnformatted(track.artist)}
	if imgui.TableSetColumnIndex(auto_cast Track_Column.Genre) {imgui.TextUnformatted(track.genre)}

	if imgui.TableSetColumnIndex(auto_cast Track_Column.Duration) {
		hours, minutes, seconds := time.clock_from_seconds(auto_cast track.duration_seconds)
		imgui.Text("%02d:%02d:%02d", i32(hours), i32(minutes), i32(seconds))
	}

	if imgui.TableSetColumnIndex(auto_cast Track_Column.Title) {
		it.visible = true

		if pb.playing_track == it.track {
			imgui.TableSetBgColor(.RowBg0, theme.get_color_u32(.PlayingHighlight))
		}

		imgui.Selectable(track.title, slice.contains(it.selection, it.track), {.SpanAllColumns})
	}

	return true
}

_end_track_table :: proc(iterator: ^_Track_Table_Iterator) {
	imgui.ListClipper_End(iterator._list_clipper)
	imgui.EndTable()
	free(iterator._list_clipper)
}
