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

import "core:math/linalg"
import "core:log"
import "core:reflect"
import "core:strconv"
import "core:thread"
import "core:math"
import "core:fmt"
import glm "core:math/linalg/glsl"

import imgui "src:thirdparty/odin-imgui"

import "src:analysis"
import "src:decoder"
import "src:server"
import "src:sys"

import "imx"

@(private="file")
WINDOW_SIZE :: 8192
SPECTRUM_MAX_BANDS :: 100
MAX_OSCILLOSCOPE_SAMPLES :: 4096

Analysis_State :: struct {
	channels, samplerate: int,

	peaks: [server.MAX_OUTPUT_CHANNELS]f32,
	need_update_peaks: bool,

	window_w: [WINDOW_SIZE]f32,
	window_data: [server.MAX_OUTPUT_CHANNELS][WINDOW_SIZE]f32,
	raw_window_data: [server.MAX_OUTPUT_CHANNELS][WINDOW_SIZE]f32,
	
	fft: analysis.FFT_State,
}

@(private="file")
_hann_window :: proc(output: []f32) {
	N := f32(len(output))
	for i in 0..<len(output) {
		n := f32(i)
		output[i] = 0.5 * (1 - math.cos_f32((2 * math.PI * n) / (N - 1)))
	}
}

@(private="file")
_welch_window :: proc(output: []f32) {
	N := f32(len(output))
	N_2 := N/2

	for i in 0..<len(output) {
		n := f32(i)
		t := (n - N_2)/(N_2)
		output[i] = 1 - (t*t*t)
	}
}

@(private="file")
_osc_window :: proc(output: []f32) {
	N: f32
	margin := len(output)/10
	end_of_middle := len(output)-margin
	N = f32(margin)

	for i in 0..<margin {
		n := f32(i)
		output[i] = n/N
	}

	for i in margin..<end_of_middle {
		output[i] = 1
	}

	for i in end_of_middle..<len(output) {
		n := f32(i-end_of_middle)
		output[i] = 1 - (n/N)
	}
}

analysis_init :: proc(state: ^Analysis_State) {
	// Hann window
	_hann_window(state.window_w[:])

	analysis.fft_init(&state.fft, WINDOW_SIZE)
}

analysis_destroy :: proc(state: ^Analysis_State) {
	analysis.fft_destroy(&state.fft)
}

update_analysis :: proc(cl: ^Client, sv: ^Server, delta: f32) -> bool {
	state := &cl.analysis
	settings := &cl.settings
	tick := cl.tick_last_frame

	if server.is_paused(sv^) {return false}

	state.samplerate, state.channels = server.audio_time_frame_from_playback(sv, state.window_data[:], tick, delta) or_return
	state.raw_window_data = state.window_data

	t := clamp(30*delta, 0, 1)

	// Peak
	if state.need_update_peaks {
		state.need_update_peaks = false
		for ch in 0..<state.channels {
			peak := analysis.calc_peak(state.window_data[ch][:1024])
			state.peaks[ch] = math.lerp(state.peaks[ch], peak, t)
		}
	}
	
	// Apply window multipliers
	for ch in 0..<1 {
		for &f, i in state.window_data[ch] {
			f *= state.window_w[i]
		}
	}
	
	analysis.fft_process(&state.fft, state.window_data[0][:])

	return true
}

Wavebar_Window :: struct {
	using base: Window_Base,
	calc_thread: ^thread.Thread,
	calc_state: analysis.Calc_Peaks_State,
	dec: decoder.Decoder,
	// The length of this array corresponds to the resolution of the output waveform
	output: [1080]f32,
	track_id: Track_ID,
}

@(private="file")
_calc_wave_thread_proc :: proc(thread_data: ^thread.Thread) {
	state := cast(^Wavebar_Window) thread_data.data
	analysis.calc_peaks_over_time(&state.dec, state.output[:], &state.calc_state)
}

WAVEBAR_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Wave Bar",
	internal_name = WINDOW_WAVEBAR,
	make_instance = wavebar_window_make_instance_proc,
	show = wavebar_window_show_proc,
	hide = wavebar_window_hide_proc,
}

wavebar_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Wavebar_Window, allocator)
}

wavebar_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	wavebar_window_show(sv, auto_cast self)
}

wavebar_window_hide_proc :: proc(self: ^Window_Base) {
}

wavebar_window_show :: proc(sv: ^Server, state: ^Wavebar_Window) -> (ok: bool) {
	track_id := sv.current_track_id

	if state.calc_thread != nil && thread.is_done(state.calc_thread) {
		thread.destroy(state.calc_thread)
		state.calc_thread = nil

		decoder.close(&state.dec)
	}

	if track_id != state.track_id {
		state.track_id = track_id
		for &f in state.output {f = 0}
		if track_id != 0 {
			if state.calc_thread != nil {
				state.calc_state.want_cancel = true
				if !thread.is_done(state.calc_thread) {thread.join(state.calc_thread)}
				thread.destroy(state.calc_thread)
				state.calc_state = {}
				state.calc_thread = nil

				decoder.close(&state.dec)
			}

			state.calc_thread = thread.create(_calc_wave_thread_proc)
			state.calc_thread.data = state
			state.calc_thread.init_context = context
			state.calc_state = {}
			defer if !ok {thread.destroy(state.calc_thread); state.calc_thread = nil}

			path_buf: [512]u8
			path := server.library_find_track_path(sv.library, path_buf[:], state.track_id) or_return
			decoder.open(&state.dec, path, nil) or_return

			ok = true

			thread.start(state.calc_thread)
		}
	}

	if state.track_id == 0 {return}

	position := f32(server.get_track_second(sv))
	duration := f32(server.get_track_duration_seconds(sv))

	if imx.wave_seek_bar(
		"##waveform", state.output[:], &position, duration,
		global_theme.custom_colors[.WavebarQuiet],
		global_theme.custom_colors[.WavebarLoud]
	) {
		server.seek_to_second(sv, int(position))
	}

	return true
}

Oscilloscope_Channel_Mode :: enum {
	Mono,
	Separate,
	Overlapped,
}

Oscilloscope_Window :: struct {
	using base: Window_Base,
	sample_count: int,
	window_w: [dynamic]f32,
	channel_mode: Oscilloscope_Channel_Mode,
}

OSCILLOSCOPE_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Oscilloscope",
	internal_name = WINDOW_OSCILLOSCOPE,
	make_instance = oscilloscope_window_make_instance_proc,
	save_config = oscilloscope_window_save_config_proc,
	configure = oscilloscope_window_configure_proc,
	show = oscilloscope_window_show_proc,
	hide = oscilloscope_window_hide_proc,
	flags = {.MultiInstance, .NoInitialInstance},
}

oscilloscope_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Oscilloscope_Window, allocator)
}

oscilloscope_window_configure_proc :: proc(self: ^Window_Base, key, value: string) {
	state := cast(^Oscilloscope_Window) self

	if key == "Resolution" {
		state.sample_count = clamp(strconv.parse_int(value) or_else 0, 0, MAX_OSCILLOSCOPE_SAMPLES)
	}
	else if key == "ChannelMode" {
		if value, ok := reflect.enum_from_name(Oscilloscope_Channel_Mode, value); ok {
			state.channel_mode = value
		}
	}
}

oscilloscope_window_save_config_proc :: proc(self: ^Window_Base, out_buf: ^imgui.TextBuffer) {
	state := cast(^Oscilloscope_Window) self
	channel_mode_buf: [64]u8
	copy(channel_mode_buf[:63], reflect.enum_name_from_value(state.channel_mode) or_else "")

	imgui.TextBuffer_appendf(out_buf, "Resolution=%d\n", i32(state.sample_count))
	imgui.TextBuffer_appendf(out_buf, "ChannelMode=%s\n", cstring(&channel_mode_buf[0]))
}

oscilloscope_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Oscilloscope_Window) self
	input := cl.analysis.raw_window_data[:]
	drawlist := imgui.GetWindowDrawList()

	if state.sample_count == 0 {state.sample_count = MAX_OSCILLOSCOPE_SAMPLES}
	if len(state.window_w) != state.sample_count {
		resize(&state.window_w, state.sample_count)
		_osc_window(state.window_w[:])
	}

	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Channels")
		if imgui.MenuItem("Mono") {state.channel_mode = .Mono}
		if imgui.MenuItem("Overlapped") {state.channel_mode = .Overlapped}
		if imgui.MenuItem("Separate") {state.channel_mode = .Separate}
		imgui.Separator()
		if imgui.BeginMenu("Resolution") {
			if imgui.MenuItem("256") {state.sample_count = 256}
			if imgui.MenuItem("512") {state.sample_count = 512}
			if imgui.MenuItem("1024") {state.sample_count = 1024}
			if imgui.MenuItem("2048") {state.sample_count = 2048}
			if imgui.MenuItem("4096") {state.sample_count = 4096}
			imgui.EndMenu()
		}

		imgui.EndPopup()
	}

	draw_osc_line :: proc(drawlist: ^imgui.DrawList, input: []f32, size: imgui.Vec2, color: u32) {
		y_offset := size.y * 0.5
		x_offset: f32 = 0
		cursor := imgui.GetCursorScreenPos()
		gap := size.x / f32(len(input))
		y_mul := size.y * 0.5

		for i in 0..<(len(input)-1) {
			a := input[i]
			b := input[i+1]
			p1 := cursor + {x_offset, y_offset + y_mul * a}
			p2 := cursor + {x_offset + gap, y_offset + y_mul * b}
			imgui.DrawList_AddLine(drawlist, p1, p2, color, 2)
			x_offset += gap
		}
	}

	switch state.channel_mode {
		case .Mono: {
			draw_osc_line(
				drawlist, input[0][:state.sample_count],
				imgui.GetContentRegionAvail(), imgui.GetColorU32(.PlotLines)
			)
		}
		case .Overlapped: {
			size := imgui.GetContentRegionAvail()
			colors := [server.MAX_OUTPUT_CHANNELS]u32 {
				imgui.GetColorU32(.PlotLines, 0.8),
				imgui.GetColorU32(.PlotLinesHovered, 0.5),
			}

			for ch in 0..<cl.analysis.channels {
				draw_osc_line(drawlist, input[ch][:state.sample_count], size, colors[ch])
			}
		}
		case .Separate: {
			size := imgui.GetContentRegionAvail()
			size.y /= f32(cl.analysis.channels)

			for ch in 0..<cl.analysis.channels {
				draw_osc_line(drawlist, input[ch][:state.sample_count], size, imgui.GetColorU32(.PlotLines))
				imgui.Dummy(size)
			}
		}
	}
}

oscilloscope_window_hide_proc :: proc(self: ^Window_Base) {
	state := cast(^Oscilloscope_Window) self
	delete(state.window_w)
	state.window_w = nil
}

Spectrum_Display_Mode :: enum {
	Bars,
	Alpha,
}

Spectrum_Band_Distribution :: enum {
	Uniform,
	Natural,
}

Spectrum_Window :: struct {
	using base: Window_Base,
	band_freqs: [SPECTRUM_MAX_BANDS]f32,
	band_freq_guides: [SPECTRUM_MAX_BANDS][8]u8,
	band_heights: [SPECTRUM_MAX_BANDS]f32,
	band_freqs_calculated: int,
	band_count: int,
	display_mode: Spectrum_Display_Mode,
	band_distribution: Spectrum_Band_Distribution,
	band_scaling_factor: f32,
	interpolation_speed: f32,
	should_interpolate: bool,
}

SPECTRUM_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Spectrum",
	internal_name = WINDOW_SPECTRUM,
	configure = spectrum_window_configure_proc,
	save_config = spectrum_window_save_config_proc,
	make_instance = spectrum_window_make_instance_proc,
	show = spectrum_window_show_proc,
	hide = spectrum_window_hide_proc,
	flags = {.MultiInstance, .NoInitialInstance},
}

spectrum_window_configure_proc :: proc(self: ^Window_Base, key: string, value: string) {
	state := cast(^Spectrum_Window) self

	if key == "BandCount" {
		state.band_count = strconv.parse_int(value) or_else state.band_count
	}
	else if key == "DisplayMode" {
		state.display_mode = reflect.enum_from_name(Spectrum_Display_Mode, value) or_else state.display_mode
	}
	else if key == "BandDistribution" {
		state.band_distribution = reflect.enum_from_name(
			Spectrum_Band_Distribution,
			value
		) or_else state.band_distribution
	}
	else if key == "NaturalScalingFactor" {
		state.band_scaling_factor = strconv.parse_f32(value) or_else state.band_scaling_factor
	}
	else if key == "ApplyInterp" {
		state.should_interpolate = (strconv.parse_int(value) or_else int(state.should_interpolate)) != 0
	}
	else if key == "InterpSpeed" {
		state.interpolation_speed = strconv.parse_f32(value) or_else state.interpolation_speed
	}
}

spectrum_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	ret := new(Spectrum_Window, allocator)
	ret.band_scaling_factor = 2.5
	ret.interpolation_speed = 30
	return ret
}

spectrum_window_save_config_proc :: proc(self: ^Window_Base, out_buf: ^imgui.TextBuffer) {
	state := cast(^Spectrum_Window) self
	enum_name_buf: [32]u8

	imgui.TextBuffer_appendf(out_buf, "BandCount=%d\n", i32(state.band_count))
	imgui.TextBuffer_appendf(out_buf, "ApplyInterp=%d\n", i32(state.should_interpolate))
	imgui.TextBuffer_appendf(out_buf, "InterpSpeed=%d\n", i32(state.interpolation_speed))
	imgui.TextBuffer_appendf(out_buf, "DisplayMode=%s\n", enum_cstring(enum_name_buf[:], state.display_mode))
	imgui.TextBuffer_appendf(out_buf, "BandDistribution=%s\n", enum_cstring(enum_name_buf[:], state.band_distribution))
	imgui.TextBuffer_appendf(out_buf, "NaturalScalingFactor=%f\n", state.band_scaling_factor)
}

spectrum_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Spectrum_Window) self
	real_band_heights: [SPECTRUM_MAX_BANDS]f32
	band_colors: [SPECTRUM_MAX_BANDS]u32

	if state.band_count <= 10 || state.band_count > SPECTRUM_MAX_BANDS {state.band_count = SPECTRUM_MAX_BANDS}

	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Display mode")
		if imgui.MenuItem("Bar graph", nil, state.display_mode == .Bars) {state.display_mode = .Bars}
		if imgui.MenuItem("Alpha", nil, state.display_mode == .Alpha) {state.display_mode = .Alpha}
		imgui.SeparatorText("No. bands")
		if imgui.MenuItem("20", nil, state.band_count == 20) {state.band_count = 20}
		if imgui.MenuItem("40", nil, state.band_count == 40) {state.band_count = 40}
		if imgui.MenuItem("60", nil, state.band_count == 60) {state.band_count = 60}
		if imgui.MenuItem("80", nil, state.band_count == 80) {state.band_count = 80}
		if imgui.MenuItem("100", nil, state.band_count == 100) {state.band_count = 100}
		imgui.SeparatorText("Band size")
		if imgui.MenuItem("Uniform", nil, state.band_distribution == .Uniform) {state.band_distribution = .Uniform}
		if imgui.MenuItem("Natural", nil, state.band_distribution == .Natural) {state.band_distribution = .Natural}
		imgui.SeparatorText("Parameters")
		if imgui.DragFloat("Natural scaling factor", &state.band_scaling_factor, 0.5, 0, 10) {
			state.band_distribution = .Natural
		}
		imgui.Checkbox("Apply interpolation", &state.should_interpolate)
		imgui.SetItemTooltip("When enabled: smooths the movement of bands to reduce flashing/flickering")
		if imgui.DragFloat("Interpolation speed", &state.interpolation_speed, 1, 1, 50) {
			state.should_interpolate = true
		}

		imgui.EndPopup()
	}

	if state.band_freqs_calculated != state.band_count {
		state.band_freqs_calculated = state.band_count
		analysis.calc_spectrum_frequencies(state.band_freqs[:state.band_count])

		// Frequency guides
		for freq_raw, i in state.band_freqs[:state.band_count] {
			freq := math.floor(freq_raw)
			guide := &state.band_freq_guides[i]
			for &c in guide {c = 0}
			if freq > 1_000 {
				fmt.bprintf(guide[:len(guide)-1], "%.1fK", freq/1_000)
			}
			else {
				fmt.bprintf(guide[:len(guide)-1], "%.0f", freq)
			}
		}
	}

	analysis.fft_extract_bands(
		cl.analysis.fft, state.band_freqs[:state.band_count],
		auto_cast cl.analysis.samplerate, real_band_heights[:state.band_count]
	)

	// Apply interpolation if needed
	if state.should_interpolate {
		for band, i in real_band_heights[:state.band_count] {
			state.band_heights[i] = safe_lerp(
				state.band_heights[i], band,
				cl.delta * state.interpolation_speed
			)
		}
	}
	else {
		copy(state.band_heights[:state.band_count], real_band_heights[:state.band_count])
	}

	// Band colors
	{
		loud := global_theme.custom_colors[.PeakLoud]
		quiet := global_theme.custom_colors[.PeakQuiet]

		for &band, i in state.band_heights[:state.band_count] {
			band_colors[i] = imgui.GetColorU32ImVec4(linalg.lerp(quiet, loud, band))
		}
	}

	drawlist := imgui.GetWindowDrawList()

	distribute_band_widths :: proc(
		total_width: f32, output: []f32,
		mode: Spectrum_Band_Distribution,
		factor: f32,
	) {
		switch mode {
			case .Uniform:
				x := total_width / f32(len(output))
				for &f in output {f = x}
			case .Natural:
				N := f32(len(output))
				exp: f32 = (N-factor)/N
				sum: f32

				output[0] = math.pow(exp, N)
				for i in 1..<len(output) {
					output[i] = output[i-1] * exp
				}

				for f in output {sum += f}
				m := total_width / sum
				for &f in output {
					f *= m
					f = max(f, 2)
				}
		}
	}

	draw_spectrum_bar_graph :: proc(
		drawlist: ^imgui.DrawList,
		pos: imgui.Vec2, size: imgui.Vec2, bands: []f32,
		band_width: []f32,
		band_colors: []u32,
		guide_font: ^imgui.Font,
	) {
		x_offset: f32 = 0

		imgui.PushFont(guide_font)
		defer imgui.PopFont()

		db_guides := []cstring {
			"0db",
			"-10db",
			"-20db",
			"-30db",
			"-40db",
			"-50db",
		}
		guide_spacing := size.y / f32(len(db_guides))
		for _, i in db_guides {
			y := guide_spacing * f32(i)
			imgui.DrawList_AddLine(drawlist,
				{pos.x, pos.y + y},
				{pos.x, pos.y + y} + {size.x, 0},
				imgui.GetColorU32(.TableBorderLight),
			)
		}

		for band, i in bands {
			width := band_width[i]
			spacing: f32 = 1

			imgui.DrawList_AddRectFilled(
				drawlist,
				{pos.x + x_offset, pos.y + size.y},
				{pos.x + x_offset + width - spacing, pos.y + size.y - (size.y * band)},
				band_colors[i],
			)
			x_offset += width
		}

		for guide, i in db_guides {
			y := guide_spacing * f32(i)
			str_size := imgui.CalcTextSize(guide) + {4, 0}
			imgui.DrawList_AddText(drawlist, {pos.x + size.x - str_size.x, pos.y + y + 4}, imgui.GetColorU32(.Text), guide)
		}
	}

	draw_spectrum_fading_bars :: proc(
		drawlist: ^imgui.DrawList,
		pos: imgui.Vec2, size: imgui.Vec2, bands: []f32,
		band_width: []f32,
		band_colors: []u32,
	) {
		x_offset: f32 = 0

		for band, i in bands {
			width := band_width[i]
			spacing: f32 = 1
			
			imgui.DrawList_AddRectFilled(
				drawlist,
				{pos.x + x_offset, pos.y},
				{pos.x + x_offset + width - spacing, pos.y + size.y},
				imgui.GetColorU32ImU32(band_colors[i], band),
			)
			x_offset += width
		}
	}
	
	band_width: [SPECTRUM_MAX_BANDS]f32

	window_pos := imgui.GetCursorScreenPos()
	window_size := imgui.GetContentRegionAvail()
	graph_size := window_size

	graph_size.y -= 16
	if graph_size.x < 20 || graph_size.y < 20 {return}
	
	distribute_band_widths(
		graph_size.x, band_width[:state.band_count],
		state.band_distribution, state.band_scaling_factor
	)

	// Draw frequency guides
	{
		imgui.PushFont(cl.mini_font)
		defer imgui.PopFont()

		text_height := imgui.GetTextLineHeight()
		min_spacing: f32 = 30
		x_accum := min_spacing
		
		pos := [2]f32{window_pos.x, window_pos.y + window_size.y - text_height}
		imgui.DrawList_AddText(drawlist, pos + {window_size.x - 20, 0}, imgui.GetColorU32(.Text), "20K")

		for &guide, i in state.band_freq_guides[0:state.band_count] {
			width := band_width[i]
			x_accum += width
			
			if x_accum >= min_spacing {
				x_accum = 0
				imgui.DrawList_AddText(drawlist, pos, imgui.GetColorU32(.Text), cstring(&guide[0]))
			}
			pos.x += width
			if pos.x > (window_pos.x + window_size.x - min_spacing*1.5) {break}
		}
	}

	switch state.display_mode {
		case .Bars: {
			draw_spectrum_bar_graph(
				drawlist, imgui.GetCursorScreenPos(),
				graph_size,
				state.band_heights[:state.band_count],
				band_width[:state.band_count],
				band_colors[:state.band_count],
				cl.mini_font,
			)
		}
		case .Alpha: {
			draw_spectrum_fading_bars(
				drawlist, imgui.GetCursorScreenPos(),
				graph_size,
				state.band_heights[:state.band_count],
				band_width[:state.band_count],
				band_colors[:state.band_count],
			)
		}
	}
}

spectrum_window_hide_proc :: proc(self: ^Window_Base) {
}

VECTORSCOPE_MAX_SAMPLES :: 1024

Vectorscope_Display_Mode :: enum {
	Sprite,
	Mirage,
}

Vectorscope_Window :: struct {
	using base: Window_Base,
	samples: [VECTORSCOPE_MAX_SAMPLES][2]f32,
	sample_count: int,
	display_mode: Vectorscope_Display_Mode,
}

VECTORSCOPE_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Vectorscope",
	internal_name = WINDOW_VECTORSCOPE,
	make_instance = vectorscope_window_make_instance,
	show = vectorscope_window_show,
	save_config = vectorscope_window_save_config,
	configure = vectorscope_window_configure,
	flags = {.NoInitialInstance},
}

vectorscope_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	win := new(Vectorscope_Window, allocator)
	win.sample_count = 256
	return win
}

vectorscope_window_configure :: proc(self: ^Window_Base, key, value: string) {
	state := cast(^Vectorscope_Window) self

	if key == "Samples" {
		state.sample_count = strconv.parse_int(value) or_else state.sample_count
	}
	else if key == "Mode" {
		state.display_mode = reflect.enum_from_name(Vectorscope_Display_Mode, value) or_else state.display_mode
	}
}

vectorscope_window_save_config :: proc(self: ^Window_Base, out_buf: ^imgui.TextBuffer) {
	state := cast(^Vectorscope_Window) self
	b: [64]u8

	imgui.TextBuffer_appendf(out_buf, "Samples=%d\n", i32(state.sample_count))
	imgui.TextBuffer_appendf(out_buf, "Mode=%s\n", enum_cstring(b[:], state.display_mode))
}

vectorscope_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Vectorscope_Window) self
	window: [2][]f32
	padding := [2]f32{30, 30}
	size := imgui.GetContentRegionAvail() - (padding * 2)

	if size.x < 10 || size.y < 10 {
		return
	}

	if cl.analysis.channels != 2 {
		imgui.TextDisabled(
			"Vectorscope is designed for stereo output (your output is %d channels)",
			i32(cl.analysis.channels)
		)
		return
	}

	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Mode")
		if imgui.MenuItem("Mirage", nil, state.display_mode == .Mirage) {state.display_mode = .Mirage}
		if imgui.MenuItem("Sprite", nil, state.display_mode == .Sprite) {state.display_mode = .Sprite}
		imgui.SeparatorText("Sample count")
		if imgui.MenuItem("256", nil, state.sample_count == 256) {state.sample_count = 256}
		if imgui.MenuItem("512", nil, state.sample_count == 512) {state.sample_count = 512}
		if imgui.MenuItem("1024", nil, state.sample_count == 1024) {state.sample_count = 1024}
		imgui.EndPopup()
	}

	state.sample_count = clamp(state.sample_count, 1, VECTORSCOPE_MAX_SAMPLES)

	for ch in 0..<2 {
		window[ch] = cl.analysis.raw_window_data[ch][:state.sample_count]
	}

	for ch_data, ch in window {
		for f, i in ch_data {
			state.samples[i][ch] = f
		}
	}

	project_sample_to_screen_mirage :: proc(
		center: imgui.Vec2,
		size: imgui.Vec2,
		sample: [2]f32
	) -> [2]f32 {
		v: [2]f32
		n := glm.normalize(sample)
		v.x = (n[1] - n[0]) * 0.75
		if abs(sample[1]) > abs(sample[0]) {
			v.y = sample[1]
		}
		else {
			v.y = sample[0]
		}
		
		return center + (v * size * 0.5)
	}

	project_sample_to_screen_cross :: proc(
		center: imgui.Vec2,
		size: imgui.Vec2,
		sample: [2]f32
	) -> [2]f32 {
		s: f32 = 0.70710678119 // cos(pi/4), sin(pi/4)
		v := [2]f32 {
			sample[0] * s - sample[1] * s,
			sample[0] * s + sample[1] * s,
		}
		v.x = clamp(v.x * 0.7, -1, 1)
		v.y = clamp(v.y * 0.7, -1, 1)
		return center + (v * size * 0.5)
	}

	draw_vectorscope :: proc(
		drawlist: ^imgui.DrawList,
		pos: imgui.Vec2,
		size: imgui.Vec2,
		samples: [][2]f32,
		mode: Vectorscope_Display_Mode,
	) {
		bb := imgui.Rect{pos, pos + size}
		win_center := imgui.Rect_GetCenter(&bb)

		switch mode {
			case .Sprite:
			for p, i in samples {
				alpha := 1 - (f32(i) / f32(len(samples)))
				alpha = clamp(alpha, 0, 1)
				v := project_sample_to_screen_cross(win_center, size, p)
				imgui.DrawList_AddRectFilled(
					drawlist, v, v + {2, 2}, imgui.GetColorU32ImVec4(
						global_theme.custom_colors[.Vectorscope] * {1, 1, 1, alpha}
					),
				)
			}
			case .Mirage:
			for p, i in samples {
				alpha := 1 - (f32(i) / f32(len(samples)))
				alpha = clamp(alpha, 0, 1)
				v := project_sample_to_screen_mirage(win_center, size, p)
				imgui.DrawList_AddRectFilled(
					drawlist, v, v + {2, 2}, imgui.GetColorU32ImVec4(
						global_theme.custom_colors[.Vectorscope] * {1, 1, 1, alpha}
					),
				)
			}
		}
	}

	drawlist := imgui.GetWindowDrawList()
	
	pos := imgui.GetCursorScreenPos() + padding

	if state.display_mode == .Sprite {
		bb: [2]imgui.Vec2 = {
			pos,
			pos + size
		}

		imgui.DrawList_AddLine(
			drawlist,
			bb[0],
			bb[1],
			imgui.GetColorU32(.TableBorderLight, 0.5),
		)

		imgui.DrawList_AddLine(
			drawlist,
			{bb[1].x, bb[0].y},
			{bb[0].x, bb[1].y},
			imgui.GetColorU32(.TableBorderLight, 0.5),
		)

		imgui.PushFont(cl.mini_font)
		defer imgui.PopFont()

		imgui.DrawList_AddText(
			drawlist,
			bb[0], imgui.GetColorU32(.Text),
			"-L"
		)

		imgui.DrawList_AddText(
			drawlist,
			bb[1], imgui.GetColorU32(.Text),
			"+L"
		)

		imgui.DrawList_AddText(
			drawlist,
			{bb[0].x, bb[1].y}, imgui.GetColorU32(.Text),
			"-R"
		)

		imgui.DrawList_AddText(
			drawlist,
			{bb[1].x, bb[0].y}, imgui.GetColorU32(.Text),
			"+R"
		)
	}

	draw_vectorscope(
		drawlist,
		pos, size,
		state.samples[:state.sample_count],
		state.display_mode,
	)
}

SPECTOGRAM_BANDS :: 256

Spectogram_Window :: struct {
	using base: Window_Base,
	view_start: int,
	resolution: int,
	band_count: int,
	band_frequencies: [SPECTOGRAM_BANDS]f32,
	band_frequencies_calculated: int,
	buffer: imgui.TextureID,
}

SPECTOGRAM_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Spectogram",
	internal_name = WINDOW_SPECTOGRAM,
	make_instance = spectogram_window_make_instance,
	show = spectogram_window_show,
	flags = {.NoInitialInstance},
}

spectogram_window_make_instance :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Spectogram_Window, allocator)
}

spectogram_window_show :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Spectogram_Window) self
	cursor := imgui.GetCursorScreenPos()
	size := imgui.GetContentRegionAvail()
	drawlist := imgui.GetWindowDrawList()
	column: [SPECTOGRAM_BANDS]u32

	defer {
		state.view_start += 1
		if state.view_start >= state.resolution {
			state.view_start = 0
		}
	}

	state.resolution = clamp(state.resolution, 1024, 2048)
	state.band_count = SPECTOGRAM_BANDS
	
	if state.buffer == 0 {
		ok: bool
		state.buffer, ok = sys.video_create_dynamic_texture(state.band_count, state.resolution)
		if !ok {return}
	}

	if state.band_frequencies_calculated != SPECTOGRAM_BANDS {
		analysis.calc_spectrum_frequencies(state.band_frequencies[:])
		state.band_frequencies_calculated = SPECTOGRAM_BANDS
	}

	
	frequencies := state.band_frequencies
	bands: [SPECTOGRAM_BANDS]f32

	analysis.fft_extract_bands(cl.analysis.fft, frequencies[:], f32(cl.analysis.samplerate), bands[:])

	for b, i in bands {
		column[i] = imgui.GetColorU32ImU32(max(u32), b)
	}

	sys.video_update_dynamic_texture(
		state.buffer, {0, state.view_start}, {SPECTOGRAM_BANDS, 1}, raw_data(column[:])
	)

	ratio := f32(state.view_start) / f32(state.resolution)

	draw_partial_quad :: proc(
		drawlist: ^imgui.DrawList,
		texture: imgui.TextureID,
		pos: [2]f32,
		size: [2]f32,
		ratio: f32,
		offset: f32,
	) {
		midpoint := pos.x + (size.x * ratio)
		
		imgui.DrawList_AddCallback(
			drawlist,
			sys.video_imgui_callback_override_sampler,
			nil, 0,
		)
		
		imgui.DrawList_AddImageQuad(
			drawlist, texture,
			pos,
			{pos.x + size.x, pos.y},
			{pos.x + size.x, pos.y + size.y},
			{pos.x, pos.y + size.y},
			{1, ratio - 0.5}, {1, ratio}, {0, ratio}, {0, ratio - 0.5}
		)

	}

	draw_partial_quad(drawlist, state.buffer, cursor, size, ratio, 0)
}
