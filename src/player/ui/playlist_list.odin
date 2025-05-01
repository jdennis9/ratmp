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

import "core:hash/xxhash"
import "core:log"

import imgui "libs:odin-imgui"

import "player:library"
import "player:theme"

@(private="file")
_Column_Index :: enum {Name, Length}

@(private="file")
_Column :: struct {
	name: cstring,
	weight: f32,
	sort_metric: library.Playlist_Sort_Metric,
	flags: imgui.TableColumnFlags,
}

@(private="file")
_COLUMNS := [_Column_Index]_Column {
	.Name = {name = "Name", weight = 0.9, sort_metric = .Name, flags = {.NoHide}},
	.Length = {name = "No. Tracks", weight = 0.1, sort_metric = .Length},
}

_begin_playlist_table :: proc(str_id: cstring) -> bool {
	table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Reorderable|imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp|
		imgui.TableFlags_ScrollY|imgui.TableFlags_Sortable|imgui.TableFlags_SortTristate

	if imgui.BeginTable(str_id, 2, table_flags) {
		for col in _COLUMNS {
			imgui.TableSetupColumn(col.name, col.flags, col.weight)
		}

		imgui.TableSetupScrollFreeze(1, 1)
		imgui.TableHeadersRow()

		return true
	}

	return false
}

_playlist_table_update_sort_spec :: proc(spec: ^library.Playlist_Sort_Spec) -> bool {
	table_specs := imgui.TableGetSortSpecs()
	if table_specs == nil {return false}

	if table_specs.SpecsDirty {
		specs := table_specs.Specs
		if specs == nil {
			spec.metric = .None
			return true
		}
		
		spec.metric = _COLUMNS[auto_cast specs.ColumnIndex].sort_metric
		if specs.SortDirection == .Ascending {spec.order = .Ascending}
		else if specs.SortDirection == .Descending {spec.order = .Descending}

		table_specs.SpecsDirty = false
		return true
	}

	return false
}

_playlist_table_row :: proc(playlist: library.Playlist, selected, playing: bool) -> (clicked: bool, visible: bool) {
	imgui.TableNextRow()

	if playing {
		imgui.TableSetBgColor(.RowBg0, theme.get_color_u32(.PlayingHighlight))
	}

	if imgui.TableSetColumnIndex(auto_cast _Column_Index.Length) {
		imgui.Text("%u", cast(u32) len(playlist.tracks))
	}

	if imgui.TableSetColumnIndex(auto_cast _Column_Index.Name) {
		clicked = imgui.Selectable(playlist.name, selected, {.SpanAllColumns})
		visible = true
	}

	return
}

_end_playlist_table :: proc() {
	imgui.EndTable()
}
