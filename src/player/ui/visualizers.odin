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

import "core:fmt";
import "core:strings";
import "core:math";

import "../analysis";
import imgui "../../libs/odin-imgui";

_show_spectrum_window :: proc() {
	spectrum := analysis.get_spectrum();
    drawlist := imgui.GetWindowDrawList();

    imgui.PushStyleColor(.TableHeaderBg, 0);
    defer imgui.PopStyleColor();

    imgui.PushStyleVarImVec2(.CellPadding, {});
    defer imgui.PopStyleVar();

    imgui.PushStyleVar(.TableAngledHeadersAngle, math.to_radians_f32(20));
    defer imgui.PopStyleVar();

    imgui.PushStyleVarImVec2(.TableAngledHeadersTextAlign, {0.5, 0.5});
    defer imgui.PopStyleVar();
    
    table_flags := imgui.TableFlags_BordersInner;
    if imgui.BeginTable("##spectrum_table", analysis.SPECTRUM_BANDS, table_flags) {
        for band in analysis.SPECTRUM_BAND_OFFSETS[1:] {
            buf: [32]u8;
            name: string;
            if band > 10000 {
                name = fmt.bprintf(buf[:31], "%dK", int(f32(band)/1000));
            }
            else if band > 1000 {
                name = fmt.bprintf(buf[:31], "%1.1fK", f32(band)/1000);
            }
            else {
                name = fmt.bprintf(buf[:31], "%d", band);
            }
            imgui.TableSetupColumn(strings.unsafe_string_to_cstring(name), {.AngledHeader});
        }
        
        imgui.TableAngledHeadersRow();
        
        imgui.TableNextRow();
        for &band, index in spectrum.peaks {
            freq := analysis.SPECTRUM_BAND_OFFSETS[index+1];

            if imgui.TableNextColumn() {
                size := imgui.GetContentRegionAvail();
                cursor := imgui.GetCursorScreenPos();
                imgui.DrawList_AddRectFilled(drawlist, 
                    {cursor.x, cursor.y + size.y}, 
                    {cursor.x + size.x, cursor.y + size.y * (1 - band)},
                    imgui.GetColorU32(.PlotHistogram),
                );
            }
        }

        imgui.EndTable();
    }
}

_show_spectrum_widget :: proc(str_id: cstring, req_size: [2]f32) -> bool {
    avail_size := imgui.GetContentRegionAvail();
    cursor := imgui.GetCursorScreenPos();
    drawlist := imgui.GetWindowDrawList();
    spectrum := analysis.get_spectrum();
    //imgui.PushStyleColor(.FrameBg, 0);
    //imgui.PlotHistogram(str_id, &spectrum.peaks[0], len(spectrum.peaks), {}, nil, 0, 1, {width, 0});
    //imgui.PopStyleColor();

    graph_size := [2]f32 {
        req_size.x == 0 ? avail_size.x : req_size.x,
        req_size.y == 0 ? avail_size.y : req_size.y,
    };

    band_width := graph_size.x / analysis.SPECTRUM_BANDS;
    band_width -= 1;

    for peak in spectrum.peaks {
        size := [2]f32{band_width, graph_size.y};
        imgui.DrawList_AddRectFilled(drawlist, 
            {cursor.x, cursor.y + size.y}, 
            {cursor.x + size.x, cursor.y + size.y * (1 - peak)},
            imgui.GetColorU32(.PlotHistogram),
        );
        cursor.x += band_width + 1;
    }

    return imgui.InvisibleButton(str_id, graph_size);
}

_show_peak_window :: proc() {
}
