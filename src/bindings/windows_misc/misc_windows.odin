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
package windows_misc

import "core:c"

foreign import lib "src:bindings/bindings.lib"
import win "core:sys/windows"

foreign lib {
    ole_initialize :: proc() -> win.HRESULT ---
    drag_drop_init :: proc(hwnd: win.HWND, drop: proc(path: cstring)) ---
    //get_font_file_from_name :: proc(name: cstring, buf: cstring, buf_size: i32) -> bool ---
    get_font_file_from_logfont :: proc(logfont: ^win.LOGFONTW, buf: cstring, buf_size: i32) -> bool ---
}
