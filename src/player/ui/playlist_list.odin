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

import "core:hash/xxhash"
import "core:log";

import imgui "libs:odin-imgui";

import lib "player:library";
import "player:theme";

_Playlist_List_Sort_Spec :: struct {
	metric: lib.Playlist_List_Sort_Metric,
	order: lib.Sort_Order,
};

Playlist_List_Action :: struct {
	play_playlist: Maybe(int),
	select_playlist: Maybe(int),
	sort_spec: Maybe(_Playlist_List_Sort_Spec),
	filter: string,
	filter_hash: u32,
};

_Playlist_List_Column_Index :: enum {Name, Length};
_Playlist_List_Column :: struct {
	name: cstring,
	sort_metric: lib.Playlist_List_Sort_Metric,
};

_show_playlist_row :: proc(list: lib.Playlist_List, playlist_index: int, playing_index: int, action: ^Playlist_List_Action) {
	playlist := list.playlists[playlist_index];
	imgui.TableNextRow();

	imgui.PushIDInt(auto_cast playlist_index);
	defer imgui.PopID();

	name := len(playlist.name) > 0 ? playlist.name : "<none>";

	if imgui.TableSetColumnIndex(auto_cast _Playlist_List_Column_Index.Name) {
		if playlist_index == playing_index {
			imgui.TableSetBgColor(.RowBg0, imgui.GetColorU32ImVec4(theme.custom_colors[.PlayingHighlight]));
		}

		if imgui.Selectable(name, false, {.SpanAllColumns}) {
			action.select_playlist = playlist_index;
		}
		
		// Drag-drop
		if imgui.BeginDragDropSource() {
			_set_track_drag_drop_payload(playlist.tracks[:]);
			imgui.SetTooltip("%d tracks", cast(i32) len(playlist.tracks));
			imgui.EndDragDropSource();
		}

		if imgui.IsItemClicked(.Middle) {
			action.play_playlist = playlist_index;
		}
	}

	if imgui.TableSetColumnIndex(auto_cast _Playlist_List_Column_Index.Length) {
		imgui.TextDisabled("%d", i32(len(playlist.tracks)));
	}
}

_show_playlist_list :: proc(list: lib.Playlist_List, playing_index: int) -> (action: Playlist_List_Action) {
	table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Reorderable|imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp|
		imgui.TableFlags_ScrollY|imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate;

	columns := [_Playlist_List_Column_Index]_Playlist_List_Column {
		.Length = {"No. Tracks", .Length},
		.Name = {"Name", .Name},
	};

	// -------------------------------------------------------------------------
	// Sort specs helper
	// -------------------------------------------------------------------------
	update_sort_specs :: proc(
		columns: [_Playlist_List_Column_Index]_Playlist_List_Column,
		action: ^Playlist_List_Action,
	) -> bool {
		sort_specs := imgui.TableGetSortSpecs();
		if sort_specs == nil {return false}

		if sort_specs.SpecsDirty {
			specs := sort_specs.Specs;
			if specs == nil {
				action.sort_spec = _Playlist_List_Sort_Spec{
					metric = .None,
				};
				return true;
			}
			
			out_spec := _Playlist_List_Sort_Spec{};
			out_spec.metric = columns[auto_cast specs.ColumnIndex].sort_metric;
			if specs.SortDirection == .Ascending {out_spec.order = .Ascending}
			else if specs.SortDirection == .Descending {out_spec.order = .Descending}

			action.sort_spec = out_spec;

			sort_specs.SpecsDirty = false;
			return true;
		}

		return false;
	}

	// -------------------------------------------------------------------------
	// Filter
	// -------------------------------------------------------------------------
	@static filter: [128]u8;
	@static filter_hash: u32;

	if imgui.InputTextWithHint("##filter", "Filter", cstring(&filter[0]), len(filter)) {
		filter_hash = xxhash.XXH32(transmute([]u8) string(cstring(&filter[0])));
	}

	action.filter = string(cstring(&filter[0]));
	action.filter_hash = len(action.filter) > 0 ? filter_hash : 0;

	// -------------------------------------------------------------------------
	// Playlist table
	// -------------------------------------------------------------------------
	if imgui.BeginTable("##playlist_list", 2, table_flags) {
		for col in columns {
			imgui.TableSetupColumn(col.name);
		}

		imgui.TableSetupScrollFreeze(1, 1);
		imgui.TableHeadersRow();

		update_sort_specs(columns, &action);

		if list.filter_hash == 0 {
			for _, playlist_index in list.playlists {
				_show_playlist_row(list, playlist_index, playing_index, &action);
			}
		}
		else {
			for playlist_index in list.filter_indices {
				_show_playlist_row(list, int(playlist_index), playing_index, &action);
			}
		}

		imgui.EndTable();
	}

	return;
}
