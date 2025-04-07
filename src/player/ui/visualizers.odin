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

import "../analysis";
import imgui "../../libs/odin-imgui";

_show_spectrum_window :: proc() {
	spectrum := analysis.get_spectrum();
	size := imgui.GetContentRegionAvail();
	imgui.PlotHistogram("##spectrum", &spectrum.peaks[0], auto_cast len(spectrum.peaks), {}, nil, 0, 1, size);
}

_show_peak_window :: proc() {
}
