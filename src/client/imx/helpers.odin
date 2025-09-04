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
package imgui_extensions

import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

text_unformatted :: proc(str: string) {
	n := len(str)
	if n == 0 {return}
	p := transmute([]u8) str
	end := &((raw_data(p))[len(p)])
	imgui.TextUnformatted(cstring(raw_data(p)), cstring(end))
}

text :: proc($MAX_CHARS: uint, args: ..any, sep := " ") {
	buf: [MAX_CHARS]u8 = ---
	formatted := fmt.bprint(buf[:], ..args, sep=sep)
	text_unformatted(formatted)
}

textf :: proc($MAX_CHARS: uint, format: string, args: ..any) {
	buf: [MAX_CHARS]u8 = ---
	formatted := fmt.bprintf(buf[:], format, ..args)
	text_unformatted(formatted)
}


begin_status_bar :: proc() -> bool {
	window_flags := imgui.WindowFlags{
		.NoScrollbar, 
		.NoSavedSettings, 
		.MenuBar,
	}

	imgui.BeginViewportSideBar(
		"##status_bar",
		imgui.GetMainViewport(),
		.Down,
		imgui.GetFrameHeight(),
		window_flags,
	) or_return

	return imgui.BeginMenuBar()
}

end_status_bar :: proc() {
	imgui.EndMenuBar()
	imgui.End()
}

