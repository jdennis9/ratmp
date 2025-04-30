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

import "core:fmt"
import "core:strings"
import "core:math"
import "core:log"
import glm "core:math/linalg/glsl"

import imgui "libs:odin-imgui"

import "player:analysis"
import "player:playback"
import "player:theme"
import "player:prefs"

_show_spectrum_window :: proc() {
	spectrum := analysis.get_spectrum()
    drawlist := imgui.GetWindowDrawList()

    imgui.PushStyleColor(.TableHeaderBg, 0)
    defer imgui.PopStyleColor()

    imgui.PushStyleVarImVec2(.CellPadding, {})
    defer imgui.PopStyleVar()

    imgui.PushStyleVar(.TableAngledHeadersAngle, math.to_radians_f32(20))
    defer imgui.PopStyleVar()

    imgui.PushStyleVarImVec2(.TableAngledHeadersTextAlign, {0.5, 0.5})
    defer imgui.PopStyleVar()
    
    table_flags := imgui.TableFlags_BordersInner
    if imgui.BeginTable("##spectrum_table", analysis.SPECTRUM_BANDS, table_flags) {
        for band in analysis.SPECTRUM_BAND_OFFSETS[1:] {
            buf: [32]u8
            name: string
            if band > 10000 {
                name = fmt.bprintf(buf[:31], "%dK", int(f32(band)/1000))
            }
            else if band > 1000 {
                name = fmt.bprintf(buf[:31], "%1.1fK", f32(band)/1000)
            }
            else {
                name = fmt.bprintf(buf[:31], "%d", band)
            }
            imgui.TableSetupColumn(strings.unsafe_string_to_cstring(name), {.AngledHeader})
        }
        
        imgui.TableAngledHeadersRow()
        
        imgui.TableNextRow()
        for unclamped_band, index in spectrum.peaks {
            band := clamp(unclamped_band, 0, 1)
            freq := analysis.SPECTRUM_BAND_OFFSETS[index+1]

            if imgui.TableNextColumn() {
                size := imgui.GetContentRegionAvail()
                cursor := imgui.GetCursorScreenPos()

                quiet_color := theme.custom_colors[.PeakQuiet]
                loud_color := theme.custom_colors[.PeakLoud]
                color := glm.lerp(quiet_color, loud_color, band)

                imgui.DrawList_AddRectFilled(drawlist, 
                    {cursor.x, cursor.y + size.y}, 
                    {cursor.x + size.x, cursor.y + size.y * (1 - band)},
                    imgui.GetColorU32ImVec4(color),
                )
            }
        }

        hide_slow_peaks := prefs.get_property("ui_hide_max_peaks").(bool) or_else false

        if !hide_slow_peaks && imgui.TableSetColumnIndex(0) {
            for unclamped_band in spectrum.slow_peaks {
                band := clamp(unclamped_band, 0, 1)

                cursor := imgui.GetCursorScreenPos()
                size := imgui.GetContentRegionAvail()
                y := cursor.y + (size.y * (1 - band))

                imgui.DrawList_AddLine(drawlist, 
                    {cursor.x, y}, 
                    {cursor.x + size.x, y},
                    imgui.GetColorU32(.PlotLines),
                )

                if !imgui.TableNextColumn() {break}
            }
        }

        imgui.EndTable()
    }

    if imgui.BeginPopupContextWindow() {
        hide_slow_peaks := prefs.get_property("ui_hide_max_peaks").(bool) or_else false
        show_slow_peaks := !hide_slow_peaks

        if imgui.Checkbox("Show max peaks", &show_slow_peaks) {
            prefs.set_property("ui_hide_max_peaks", !show_slow_peaks)
            imgui.CloseCurrentPopup()
        }

        imgui.EndPopup()
    }
}

_show_spectrum_widget :: proc(str_id: cstring, req_size: [2]f32) -> bool {
    avail_size := imgui.GetContentRegionAvail()
    spectrum := analysis.get_spectrum()

    graph_size := [2]f32 {
        req_size.x == 0 ? avail_size.x : req_size.x,
        req_size.y == 0 ? avail_size.y : req_size.y,
    }

    _show_bars_widget(str_id, spectrum.peaks[:], 0, 1, graph_size)

    return imgui.InvisibleButton(str_id, graph_size)
}

_show_peak_window :: proc() {
    peaks := analysis.get_channel_peaks()
    _show_bars_widget("##peaks", peaks, 0, 1)
}

_show_wave_preview_window :: proc(pb: ^Playback) {
    samples := analysis.get_waveform_preview()
    playback_pos := f32(playback.get_second(pb^))
    playback_duration := f32(playback.get_duration(pb^))

    if len(samples) > 0 {
        drawlist := imgui.GetWindowDrawList()
        size := imgui.GetContentRegionAvail()
        cursor := imgui.GetCursorScreenPos()
        style := imgui.GetStyle()

        if size.x == 0 || size.y == 0 {return}

        bar_width := size.x / f32(len(samples))
        bar_height := size.y * 0.5
        middle := cursor.y + size.y * 0.5
        x_pos := cursor.x

        current_sample := int(f32(len(samples)) * (playback_pos/playback_duration))

        for sample, index in samples {
            peak_height := sample * bar_height
            pmin := [2]f32 {x_pos, middle - peak_height}
            pmax := [2]f32 {x_pos + bar_width, middle + peak_height}

            if (abs(pmin.y - pmax.y) < 1) {
                pmin.y -= 1
                pmax.y = pmin.y + 2
            }

            color := imgui.GetStyleColorVec4(.PlotLines)^
            if index > current_sample {color.w *= 0.5}
            imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, imgui.GetColorU32ImVec4(color))
            x_pos += bar_width
        }

        if imgui.InvisibleButton("##wave", size) {
            io := imgui.GetIO()
            click_pos := io.MousePos.x - cursor.x
            ratio := clamp(click_pos / size.x, 0, 1)
            seek_second := playback_duration * ratio
            playback.seek(pb, int(seek_second))
        }
    }
}
