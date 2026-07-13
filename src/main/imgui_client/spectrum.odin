/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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
#+private file
package client

import "core:mem"
import "core:math/linalg"
import "core:fmt"
import "src:main/shared"
import imgui "src:thirdparty/odin-imgui"
import "src:dsp"
import "src:imx"

_MAX_BANDS :: 160

_Frequency_Guide :: struct {
	str: [8]u8,
	offset: f32,
}

_Display_Mode :: enum {
	Histogram,
	Heat,
	Line,
	LineFilled,
}

@private
spectrum_window_proc :: proc(ev: UI_Window_Event) -> bool {
	@static w: struct {
		bands:            [dynamic; _MAX_BANDS]f32,
		band_freqs:       [dynamic; _MAX_BANDS]f32,
		freq_guides:      [dynamic; 32]_Frequency_Guide,
		window_values:    [dynamic]f32,
		fft:              dsp.FFT_State,
		display_mode:     _Display_Mode,
		window_func:      dsp.Window_Function,
		band_gap:         f32,
		freq_guide_width: f32, // Width of spectrum window when frequency guides were built
		freq_guide_bands: int,
	}

	if ev != .Show do return false
	
	enable_band_hover_info := true
	window_func_changed    := false
	analysis               := get_analysis_data()
	temp_allocator         := get_frame_allocator()
	
	if analysis.channels == 0 do return false
	
	frame_allocator_guard()
	
	if len(w.bands) == 0 do resize(&w.bands, 80)

	// Settings
	if imgui.BeginPopupContextWindow() {
		defer imgui.EndPopup()
		enable_band_hover_info = false
		band_count := len(w.bands)

		size_options := []int {10, 20, 40, 60, 80, 100, 140, 160}
		imgui.SeparatorText("No. Bands")
		if imx.number_picker_menu_items(size_options, &band_count) {
			resize(&w.bands, band_count)
		}

		imgui.Separator()

		if imgui.BeginMenu("Window") {
			defer imgui.EndMenu()

			items := []imx.Enum_Menu_Item(dsp.Window_Function) {
				{value=.Blackman, name="Blackman (default)"},
				{value=.Nuttall,  name="Nuttall"},
				{value=.Hamming,  name="Hamming"},
				{value=.Hann,     name="Hann"},
				{},
				{value=.Normal,   name="None"},
			}

			window_func_changed |= imx.show_enum_menu_items_ex(items, &w.window_func)
		}

		if imgui.BeginMenu("Mode") {
			defer imgui.EndMenu()
			
			items := []imx.Enum_Menu_Item(_Display_Mode) {
				{value=.Histogram,  name="Histogram"},
				{value=.Heat,       name="Heat map"},
				{value=.Line,       name="Line graph"},
				{value=.LineFilled, name="Line graph (filled)"},
			}

			imx.show_enum_menu_items_ex(items, &w.display_mode)
		}
	}

	input_window_size := 8192
	mono_input        := analysis.raw_output[0][:input_window_size]
	windowed_input    := make([]f32, input_window_size, temp_allocator)

	guide_font_scale :: 0.7
	style       := imgui.GetStyle()
	avail_size  := imgui.GetContentRegionAvail()
	graph_pos   := imgui.GetCursorScreenPos()
	graph_size: [2]f32 = {avail_size.x, avail_size.y - imgui.GetTextLineHeight() * guide_font_scale}
	bar_width   := graph_size.x / f32(len(w.bands)) - 1
	bar_spacing := bar_width + 1
	drawlist    := imgui.GetWindowDrawList()

	// Update window function values
	if len(w.window_values) != len(mono_input) || window_func_changed {
		if w.window_values == nil {
			w.window_values = make([dynamic]f32, context.allocator)
		}
		resize(&w.window_values, len(mono_input))
		dsp.make_window(w.window_values[:], w.window_func)
	}
	
	// Apply window function
	for input, i in mono_input {
		windowed_input[i] = input * w.window_values[i]
	}
	
	// Update band frequencies
	if len(w.band_freqs) != len(w.bands) {
		resize(&w.band_freqs, len(w.bands))
		dsp.distribute_band_frequencies(w.band_freqs[:])
	}
	
	// FFT
	for &b in w.bands do b = 0
	dsp.fft_process(&w.fft, windowed_input)
	dsp.fft_extract_bands(w.fft, w.band_freqs[:], analysis.samplerate, w.bands[:])

	// Create bands
	Band :: struct {offset, width, peak: f32}
	bands: [dynamic; _MAX_BANDS]Band

	// Calc band offsets
	{
		x_offset: f32 = 0

		for band in w.bands {
			append(&bands, Band {
				offset = x_offset,
				width = bar_width,
				peak = band,
			})

			x_offset += bar_spacing
		}
	}

	// Update guides
	if w.freq_guide_bands != len(w.band_freqs) || w.freq_guide_width != graph_size.x {
		shared.TIME_SCOPE("Build frequency guides")
		
		w.freq_guide_bands = len(w.band_freqs)
		w.freq_guide_width = graph_size.x
		min_spacing: f32 = 40
		x_accum: f32 = 10000
		x_offset: f32
		clear(&w.freq_guides)

		for freq in w.band_freqs {
			if len(w.freq_guides) == cap(w.freq_guides) do break

			x_accum += bar_spacing

			if x_accum >= min_spacing {
				guide: _Frequency_Guide
				guide.offset = x_offset
				x_accum = 0
				if freq > 10_000 {
					fmt.bprintf(guide.str[:], "%dKHz", int(freq/1000))
				}
				else if freq > 1000 {
					fmt.bprintf(guide.str[:], "%.1fKHz", freq/1000)
				}
				else {
					fmt.bprintf(guide.str[:], "%dHz", int(freq))
				}

				append(&w.freq_guides, guide)
			}

			x_offset += bar_spacing
		}
	}

	// Draw bands
	draw_band_bars :: proc(
		drawlist: ^imgui.DrawList, pos, size: [2]f32, bands: []Band
	) {
		quiet_color := imgui.ColorConvertU32ToFloat4(get_theme_color(.VolumeLow))
		loud_color  := imgui.ColorConvertU32ToFloat4(get_theme_color(.VolumeHigh))

		for band in bands {
			peak := clamp(band.peak, 0, 1)
			color := linalg.lerp(quiet_color, loud_color, clamp(peak, 0, 1))
			p_min: [2]f32 = {pos.x + band.offset, pos.y + size.y * (1 - peak)}
			p_max: [2]f32 = {pos.x + band.offset + band.width, pos.y + size.y}

			imgui.DrawList_AddRectFilled(drawlist, p_min, p_max, imgui.GetColorU32ImVec4(color))
		}
	}

	draw_band_heat :: proc(
		drawlist: ^imgui.DrawList, pos, size: [2]f32, bands: []Band
	) {
		quiet_color := imgui.ColorConvertU32ToFloat4(get_theme_color(.VolumeLow))
		loud_color  := imgui.ColorConvertU32ToFloat4(get_theme_color(.VolumeHigh))

		quiet_color.a = 0
		loud_color.a = 1

		for band in bands {
			peak := clamp(band.peak, 0, 1)
			color := linalg.lerp(quiet_color, loud_color, clamp(peak, 0, 1))
			p_min: [2]f32 = {pos.x + band.offset, pos.y}
			p_max: [2]f32 = {pos.x + band.offset + band.width, pos.y + size.y}

			imgui.DrawList_AddRectFilled(drawlist, p_min, p_max, imgui.GetColorU32ImVec4(color))
		}
	}
	
	draw_line_graph :: proc(
		drawlist: ^imgui.DrawList, pos, size: [2]f32, bands: []Band, allocator: mem.Allocator, fill: bool
	) {
		positions := make([][2]f32, len(bands), allocator)
		gap := (size.x/f32(len(bands)))
		x := pos.x
		color := imgui.GetColorU32(.PlotLines)

		if fill do imgui.DrawList_PathLineTo(drawlist, pos + {0, size.y})

		for band, i in bands {
			p := pos + {x, size.y * (1 - band.peak)}
			positions[i] = p
			if fill do imgui.DrawList_PathLineTo(drawlist, p)
			x += gap
		}

		if fill do imgui.DrawList_PathLineTo(drawlist, pos + size)

		if fill do imgui.DrawList_PathFillConcave(drawlist, get_theme_color(.VolumeHigh))

		imgui.DrawList_AddPolyline(drawlist, raw_data(positions), auto_cast len(positions), color, {}, 2)
	}

	draw_frequency_guides :: proc(
		drawlist: ^imgui.DrawList,
		guides: []_Frequency_Guide,
		pos: [2]f32,
	) {
		imx.push_font_scale(guide_font_scale)
		defer imgui.PopFont()
		color := imgui.GetColorU32(.TextDisabled)

		for &guide in guides {
			str := shared.string_from_array(guide.str[:])
			imgui.DrawList_AddText(drawlist, pos + {guide.offset, 0}, color, imx.string_to_ptrs(str))
		}
	}

	switch w.display_mode {
	case .Histogram:
		//draw_band_bars(drawlist, graph_pos, graph_size, bands[:])
		//draw_band_bars(drawlist, graph_pos, graph_size, bands[:])
		imx.draw_bars(
			drawlist, graph_pos + {0, graph_size.y}, graph_pos + {graph_size.x, 0}, w.bands[:],
			get_theme_color(.VolumeLow), get_theme_color(.VolumeHigh)
		)
	case .Heat:
		draw_band_heat(drawlist, graph_pos, graph_size, bands[:])
	case .Line:
		draw_line_graph(drawlist, graph_pos, graph_size, bands[:], temp_allocator, false)
	case .LineFilled:
		draw_line_graph(drawlist, graph_pos, graph_size, bands[:], temp_allocator, true)
	}
	draw_frequency_guides(drawlist, w.freq_guides[:], graph_pos + {0, graph_size.y + style.FramePadding.y})

	// Band info on hover
	if enable_band_hover_info do for band, band_index in bands {
		p_min := graph_pos + {band.offset, 0}
		p_max := p_min + {band.width, graph_size.y}

		if imgui.IsMouseHoveringRect(p_min, p_max) && imgui.BeginTooltip() {
			if band_index + 1 < len(w.band_freqs) {
				imx.textf(64, "Frequency: %.1f-%.1fHz", 
					w.band_freqs[band_index], w.band_freqs[band_index+1]
				)
			}
			else {
				imx.textf(64, "Frequency: %.1f+Hz", w.band_freqs[band_index])
			}
			imx.textf(64, "Gain: %.1fDb", dsp.amp_to_gain(w.bands[band_index]))

			imgui.DrawList_AddRect(drawlist, p_min, p_max, imgui.GetColorU32(.TextDisabled))
			imgui.EndTooltip()
		}
	}

	return true
}

