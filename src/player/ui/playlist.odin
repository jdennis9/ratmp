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
package ui;

import "core:slice";
import "core:hash/xxhash";

import imgui "../../libs/odin-imgui";

import lib "../library";
import "../playback";
import "../util";

Track_Table_Flag :: enum {
	NoRemove,
	//IsQueue,
	NoAddToQueue,
	NoFilter,
	NoSort,
}

Track_Table_Flags :: bit_set[Track_Table_Flag];

Playlist_Filter :: struct {
	text: string,
};

@(private="file")
Column_Index :: enum {
	Artist,
	Album,
	Title,
	Duration,
	Genre,
};

@(private="file")
Column :: struct {
	name: cstring,
	sort_metric: lib.Playlist_Sort_Metric,
	flags: imgui.TableColumnFlags,
};

_show_track_base_context_menu :: proc(playlist: lib.Playlist_ID, track: lib.Track) {
	if imgui.BeginMenu("Add to playlist") {
		targets := lib.get_playlists();
		for &target in targets {
			if target.id == playlist {continue}
			if imgui.MenuItem(target.name) {
				_add_selection_to_playlist(&target);
				lib.save_playlist(target.id);
			}
		}
		imgui.EndMenu();
	}

	if imgui.MenuItem("Refresh metadata") {
		_refresh_metadata_of_selected_tracks();
	}

	if imgui.MenuItem("Edit metadata") {
		_select_track_for_metadata_edit(track);
	}
}

_show_track_playlist_context_menu :: proc(track: lib.Track, action: ^Track_Table_Action, flags: Track_Table_Flags) {
	if (.NoAddToQueue not_in flags) && imgui.MenuItem("Add to queue") {
		action.add_to_queue |= true;
	}
}

@(private="file")
_get_selected_tracks_in_playlist :: proc(playlist: lib.Playlist) -> []lib.Track {
	out: [dynamic]lib.Track;
	defer delete(out);
	for track in playlist.tracks {
		if _is_track_selected(track) {
			append(&out, track);
		}
	}

	if len(out) == 0 {return nil}
	return slice.clone(out[:]);
}

@(private="file")
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
		imgui.TableSetBgColor(.RowBg0, PLAYING_COLOR);

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
			_show_track_base_context_menu(playlist.id, track_id);
			imgui.Separator();
			_show_track_playlist_context_menu(track_id, action, flags);

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
}

@(private="file")
_force_track_in_list_clipper :: proc(clipper: ^imgui.ListClipper, playlist: lib.Playlist, track: lib.Track, use_filter: bool) {
	index, found := slice.linear_search(playlist.tracks[:], track);

	if !found {return}

	if use_filter {
		filtered_index, found_in_filter := slice.linear_search(playlist.filter_tracks[:], index);
		if !found_in_filter {return}
		index = filtered_index;
	}

	imgui.ListClipper_ForceDisplayRangeByIndices(clipper, cast(i32) index, cast(i32) index + 1);
}

Playlist_Sort_Spec :: struct {
	metric: lib.Playlist_Sort_Metric,
	order: lib.Sort_Order,
};

Track_Table_Action :: struct {
	select_track: Maybe(int),
	play_track: Maybe(int),
	sort_spec: Maybe(Playlist_Sort_Spec),
	drag_drop_payload: []lib.Track,
	play_selection: bool,
	select_all: bool,
	add_selection_to_playlist: bool,
	drop_files: bool,
	remove: bool,
	add_to_queue: bool,

	filter: string,
	filter_hash: u32,
};

_set_track_drag_drop_payload :: proc(tracks: []lib.Track) {
	imgui.SetDragDropPayload("tracks", raw_data(tracks), size_of(lib.Track) * len(tracks));
}

_show_playlist_track_table :: proc(
	playlist: lib.Playlist,
	flags: Track_Table_Flags = {}
) -> (action: Track_Table_Action) {
	// -------------------------------------------------------------------------
	// Drag-drop
	// -------------------------------------------------------------------------
	if _begin_window_drag_drop_target("##playlist_drag_drop") {
		if imgui.AcceptDragDropPayload("selection") != nil {
			action.add_selection_to_playlist = true;
		}

		track_payload := imgui.AcceptDragDropPayload("tracks");
		if track_payload != nil && track_payload.Delivery == true {
			payload := cast([^]lib.Track) track_payload.Data;
			payload_size := track_payload.DataSize / size_of(lib.Track);
			action.drag_drop_payload = slice.clone(payload[:payload_size]);
		}

		imgui.EndDragDropTarget();
	}

	if len(playlist.tracks) == 0 {
		imgui.TextDisabled("%s is empty", playlist.name);
		if playlist.id != 0 {
			if imgui.Button("Browse library") {
				bring_window_to_front(.Library);
			}
		}
		return;
	}

	// -------------------------------------------------------------------------
	// Update filter input
	// -------------------------------------------------------------------------
	@static filter_buf: [128]u8;
	have_filter := false;

	if .NoFilter not_in flags {
		imgui.InputTextWithHint("##filter", "Filter",
			cstring(raw_data(filter_buf[:])),
			cast(uint) len(filter_buf)
		);


		filter := string(cstring(raw_data(filter_buf[:])));
		filter_hash := xxhash.XXH32((transmute([]u8) filter)[:]);
		have_filter = playlist.filter_hash != 0;

		action.filter = filter;
		action.filter_hash = filter_hash;
	}

	// -------------------------------------------------------------------------
	// Set up some variables
	// -------------------------------------------------------------------------
	select_all_filtered_tracks := false;
	playing_track := playback.get_playing_track();
	style := imgui.GetStyle();

	// -------------------------------------------------------------------------
	// Set up table
	// -------------------------------------------------------------------------

	table_flags := 
		imgui.TableFlags_Resizable|imgui.TableFlags_Hideable|
		imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Reorderable|imgui.TableFlags_ScrollY|
		imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate;
	
	if .NoSort in flags {
		table_flags &= ~(imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate);
	}

	columns := [Column_Index]Column {
		.Artist = {name = "Artist", sort_metric = .Artist},
		.Album = {name = "Album", sort_metric = .Album},
		.Title = {name = "Title", flags = {.NoHide}, sort_metric = .Title},
		.Genre = {name = "Genre", flags = {.DefaultHide}, sort_metric = .Genre},
		.Duration = {name = "Duration", sort_metric = .Duration},
	};

	// -------------------------------------------------------------------------
	// Sort specs helper
	// -------------------------------------------------------------------------
	update_sort_specs :: proc(playlist: lib.Playlist, columns: [Column_Index]Column, action: ^Track_Table_Action) -> bool {
		sort_specs := imgui.TableGetSortSpecs();
		if sort_specs == nil {return false}

		if sort_specs.SpecsDirty {
			specs := sort_specs.Specs;
			if specs == nil {
				action.sort_spec = Playlist_Sort_Spec{
					metric = .None,
				};
				return true;
			}
			
			out_spec := Playlist_Sort_Spec{};
			out_spec.metric = columns[auto_cast specs.ColumnIndex].sort_metric;
			if specs.SortDirection == .Ascending {out_spec.order = .Ascending}
			else if specs.SortDirection == .Descending {out_spec.order = .Descending}

			action.sort_spec = out_spec;

			sort_specs.SpecsDirty = false;
			return true;
		}

		return false;
	}

	// -----------------------------------------------------------------------------
	// Track table
	// -----------------------------------------------------------------------------
	str_id := len(playlist.name) > 0 ? playlist.name : "##unnamed";
	if imgui.BeginTable(str_id, cast(i32) len(Column_Index), table_flags) {
		defer imgui.EndTable();

		list_clipper: imgui.ListClipper;
		focused := imgui.IsWindowFocused();
		jump_to_playing := false;
		
		for col in columns {
			flags := col.flags;
			// This makes disabling sorting not work
			/*col.sort_metric != .None && playlist.sort_metric == col.sort_metric {
				flags |= {.DefaultSort};
				if playlist.sort_order == .Descending {flags |= {.PreferSortDescending}}
				if playlist.sort_order == .Ascending {flags |= {.PreferSortAscending}}
			}*/
			imgui.TableSetupColumn(col.name, flags);
		}
		
		imgui.TableSetupScrollFreeze(1, 1);
		imgui.TableHeadersRow();
		
		update_sort_specs(playlist, columns, &action);

		// ---------------------------------------------------------------------
		// Handle hotkeys
		// ---------------------------------------------------------------------
		if focused {
			jump_to_playing = imgui.IsKeyChordPressed(cast(i32) (imgui.Key.Space | imgui.Key.ImGuiMod_Ctrl));

			if imgui.IsKeyChordPressed(cast(i32) (imgui.Key.A | imgui.Key.ImGuiMod_Ctrl)) {
				action.select_all = true;
			}

			if .NoAddToQueue not_in flags {
				if imgui.IsKeyChordPressed(cast(i32) (imgui.Key.Q | imgui.Key.ImGuiMod_Ctrl)) {
					action.play_selection = true;
				}
			}
		}

		// ---------------------------------------------------------------------
		// Show tracks
		// ---------------------------------------------------------------------
		if !have_filter {
			imgui.ListClipper_Begin(&list_clipper, auto_cast len(playlist.tracks), imgui.GetTextLineHeightWithSpacing());

			if jump_to_playing {_force_track_in_list_clipper(&list_clipper, playlist, playing_track, false)}
			
			for imgui.ListClipper_Step(&list_clipper) {
				range_start := int(list_clipper.DisplayStart);
				range_end := int(list_clipper.DisplayEnd);
				for track_index in range_start..<range_end {
					track_id := playlist.tracks[track_index];
					selected := _is_track_selected(track_id);
					_show_track_row(&action, playlist, track_index, selected, have_filter, jump_to_playing, flags);
				}
			}
			
			imgui.ListClipper_End(&list_clipper);
		}
		else {
			imgui.ListClipper_Begin(&list_clipper, auto_cast len(playlist.filter_tracks), imgui.GetTextLineHeightWithSpacing());
			
			if jump_to_playing {_force_track_in_list_clipper(&list_clipper, playlist, playing_track, true)}

			for imgui.ListClipper_Step(&list_clipper) {
				range_start := int(list_clipper.DisplayStart);
				range_end := int(list_clipper.DisplayEnd);

				for filter_index in range_start..<range_end {
					track_index := playlist.filter_tracks[filter_index];
					track_id := playlist.tracks[track_index];
					selected := _is_track_selected(track_id);

					if select_all_filtered_tracks {_add_track_to_selection(track_id)};
					_show_track_row(&action, playlist, track_index, selected, have_filter, jump_to_playing, flags);
				}
			}

			imgui.ListClipper_End(&list_clipper);
		}
	}

	return;
}
