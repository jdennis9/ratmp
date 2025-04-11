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
package ui;

import imgui "../../libs/odin-imgui";

import lib "../library";
import "../theme";

Playlist_List_Action :: struct {
	play_playlist: Maybe(int),
	select_playlist: Maybe(int),
};

show_playlist_list :: proc(playlists: []lib.Playlist, playing_index: int) -> (action: Playlist_List_Action) {
	table_flags := imgui.TableFlags_BordersInner|imgui.TableFlags_RowBg|
		imgui.TableFlags_Reorderable|imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp|
		imgui.TableFlags_ScrollY;

	if imgui.BeginTable("##playlist_list", 2, table_flags) {
		imgui.TableSetupColumn("Title");
		imgui.TableSetupColumn("No. Tracks");
		imgui.TableSetupScrollFreeze(1, 1);
		imgui.TableHeadersRow();

		for playlist, playlist_index in playlists {
			imgui.TableNextRow();

			imgui.PushIDInt(auto_cast playlist_index);
			defer imgui.PopID();

			name := len(playlist.name) > 0 ? playlist.name : "<none>";

			imgui.TableSetColumnIndex(0);
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

			imgui.TableSetColumnIndex(1);
			imgui.TextDisabled("%d", i32(len(playlist.tracks)));
		}

		imgui.EndTable();
	}

	return;
}
