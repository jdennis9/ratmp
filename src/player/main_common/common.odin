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
package main_common;

import imgui "../../libs/odin-imgui";

import "../system_paths";
import "../prefs";
import "../theme";
import "../library";
import "../ui";
import "../video";
import "../playback";
import "../signal";

init :: proc() {
	system_paths.init();
	prefs.load();
	theme.init();
	library.init();
	playback.init();
	ui.init();
}

frame :: proc() {
	signal.post(.NewFrame);
	ui.show();
}

shutdown :: proc() {
	prefs.save();
	ui.shutdown();
	playback.shutdown();
	library.shutdown();
}
