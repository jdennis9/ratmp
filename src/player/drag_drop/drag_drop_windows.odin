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
package drag_drop;

foreign import lib "../../cpp/cpp.lib";
import win "core:sys/windows";
import imgui "../../libs/odin-imgui";

Interface :: struct {
	add_file: proc "c" (path: cstring),
	begin: proc "c" (),
	mouse_over: proc "c" (x: f32, y: f32),
	cancel: proc "c" (),
	drop: proc "c" (),
};

@(link_prefix="drag_drop_")
foreign lib {
	init_for_windows :: proc(hwnd: win.HWND) ---;
	set_interface :: proc(iface: ^Interface) ---;
}
