/*
    RAT MP - A cross-platform, extensible music player
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
package client

import imgui "src:thirdparty/odin-imgui"

Side_By_Side_Window_Mode :: enum {
	Single,
	SideBySide,
}

Side_By_Side_Window :: struct {
	left_proc: proc(state: rawptr, cl: ^Client, sv: ^Server),
	right_proc: proc(state: rawptr, cl: ^Client, sv: ^Server),
	focus_right: bool,
	data: rawptr,
	mode: Side_By_Side_Window_Mode,
}

Side_By_Side_Window_Result :: struct {
	mode: Side_By_Side_Window_Mode,
	go_back: bool,
}

side_by_side_window_show :: proc(window: Side_By_Side_Window, cl: ^Client, sv: ^Server) -> (result: Side_By_Side_Window_Result) {
	result.mode = window.mode

	switch window.mode {
		case .SideBySide: {
			imgui.BeginTable("##layout_table", 2, imgui.TableFlags_Resizable|imgui.TableFlags_SizingStretchProp) or_break
			defer imgui.EndTable()

			imgui.TableNextRow()

			if imgui.TableSetColumnIndex(0) {
				if imgui.Button(ICON_EXPAND) do result.mode = .Single
				window.left_proc(window.data, cl, sv)
			}
			if imgui.TableSetColumnIndex(1) {
				window.right_proc(window.data, cl, sv)
			}
		}
		case .Single: {
			if imgui.Button(ICON_COMPRESS) do result.mode = .SideBySide

			if window.focus_right {
				if imgui.Button("Go back") || (imgui.IsWindowFocused() && imgui.IsKeyPressed(.Escape)) {
					result.go_back = true
					break
				}
				window.right_proc(window.data, cl, sv)
			}
			else {
				window.left_proc(window.data, cl, sv)
			}
		}
	}

	return
}
