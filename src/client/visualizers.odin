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
#+private file
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

import "imx"

PEAK_ROUGHNESS :: 20
SECONDARY_PEAK_ROUGHNESS :: 1
WINDOW_SIZE :: 8192
SPECTRUM_MAX_BANDS :: 100
MAX_OSCILLOSCOPE_SAMPLES :: 4096


@private
Analysis_State :: struct {
	channels, samplerate: int,

	peaks: [server.MAX_OUTPUT_CHANNELS]f32,
	need_update_peaks: bool,

	window_w: [WINDOW_SIZE]f32,
	window_data: [server.MAX_OUTPUT_CHANNELS][WINDOW_SIZE]f32,
	raw_window_data: [server.MAX_OUTPUT_CHANNELS][WINDOW_SIZE]f32,
	
	fft: analysis.FFT_State,

	spectrum_analyzer: analysis.Spectrum_Analyser,
	spectrum_frequencies: [SPECTRUM_MAX_BANDS]f32,
	spectrum_frequency_strings: [SPECTRUM_MAX_BANDS][6]u8,
	spectrum_frequency_string_lengths: [SPECTRUM_MAX_BANDS]int,
	spectrum_frequency_bands_calculated: int,
	spectrum: [SPECTRUM_MAX_BANDS]f32,
	spectrum_smooth: [SPECTRUM_MAX_BANDS]f32,
	need_update_spectrum: bool,

	need_update_osc: bool,
	osc_input: [server.MAX_OUTPUT_CHANNELS][MAX_OSCILLOSCOPE_SAMPLES]f32,
	osc_window: [dynamic]f32,
	osc_length: int,
}

_hann_window :: proc(output: []f32) {
	N := f32(len(output))
	for i in 0..<len(output) {
		n := f32(i)
		output[i] = 0.5 * (1 - math.cos_f32((2 * math.PI * n) / (N - 1)))
	}
}

_welch_window :: proc(output: []f32) {
	N := f32(len(output))
	N_2 := N/2

	for i in 0..<len(output) {
		n := f32(i)
		t := (n - N_2)/(N_2)
		output[i] = 1 - (t*t*t)
	}
}

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

@private
analysis_init :: proc(state: ^Analysis_State) {
	window_sum: f32
	state.osc_length = MAX_OSCILLOSCOPE_SAMPLES

	// Hann window
	_hann_window(state.window_w[:])

	analysis.spectrum_analyser_init(&state.spectrum_analyzer, WINDOW_SIZE, 1/window_sum)
	analysis.fft_init(&state.fft, WINDOW_SIZE)
}

@private
analysis_destroy :: proc(state: ^Analysis_State) {
	analysis.spectrum_analyser_destroy(&state.spectrum_analyzer)
	delete(state.osc_window)
}

@private
update_analysis :: proc(cl: ^Client, sv: ^Server, delta: f32) -> bool {
	state := &cl.analysis
	settings := &cl.settings
	tick := cl.tick_last_frame

	if server.is_paused(sv^) {return false}

	state.samplerate, state.channels = server.audio_time_frame_from_playback(sv, state.window_data[:], tick, delta) or_return
	state.raw_window_data = state.window_data

	t := clamp(PEAK_ROUGHNESS*delta, 0, 1)

	
	// Peak
	if state.need_update_peaks {
		state.need_update_peaks = false
		for ch in 0..<state.channels {
			peak := analysis.calc_peak(state.window_data[ch][:1024])
			state.peaks[ch] = math.lerp(state.peaks[ch], peak, t)
		}
	}
	
	// Oscilloscope
	/*if state.need_update_osc {
		if state.osc_length == 0 {state.osc_length = 4096}
		if len(state.osc_window) != state.osc_length {
			resize(&state.osc_window, state.osc_length)
			_osc_window(state.osc_window[:])
		}
		state.need_update_osc = false
		state.samplerate, state.channels, _ = server.audio_time_frame_from_playback(sv, state.osc_input[:], tick, 0)
	}*/
	
	// Apply window multipliers
	for ch in 0..<1 {
		for &f, i in state.window_data[ch] {
			f *= state.window_w[i]
		}
	}
	
	analysis.fft_process(&state.fft, state.window_data[0][:])

	// Spectrum
	spectrum: [SPECTRUM_MAX_BANDS]f32
	if state.need_update_spectrum {
		if settings.spectrum_bands == 0 || settings.spectrum_bands != state.spectrum_frequency_bands_calculated {
			state.spectrum_frequency_bands_calculated = settings.spectrum_bands
			analysis.calc_spectrum_frequencies(state.spectrum_frequencies[:settings.spectrum_bands])
			
			// Pre-format frequency strings
			for band, index in state.spectrum_frequencies[:settings.spectrum_bands] {
				name: string

				buf := state.spectrum_frequency_strings[index][:]
				for &r in buf {r = 0}

				if band > 10000 {
					name = fmt.bprintf(buf[:len(buf)-1], "%dK", int(f32(math.round(band))/1000))
				}
				else if band > 1000 {
					name = fmt.bprintf(buf[:len(buf)-1], "%1.1fK", f32(math.round(band))/1000)
				}
				else {
					name = fmt.bprintf(buf[:len(buf)-1], "%g", math.round(band))
				}

				state.spectrum_frequency_string_lengths[index] = len(name)
			}
		}

		state.need_update_spectrum = false
		/*analysis.spectrum_analyser_calc(
			&state.spectrum_analyzer,
			state.window_data[0][:],
			state.spectrum_frequencies[:],
			spectrum[:],
			f32(state.samplerate)
		)*/
		analysis.fft_extract_bands(state.fft,
			state.spectrum_frequencies[:settings.spectrum_bands],
			f32(state.samplerate), state.spectrum[:settings.spectrum_bands]
		)

		for f, i in spectrum {
			state.spectrum[i] = clamp(0, 1, math.lerp(state.spectrum[i], f, t))
			state.spectrum_smooth[i] = clamp(0, 1, math.lerp(state.spectrum_smooth[i], f, t*0.1))
			state.spectrum_smooth[i] = max(state.spectrum_smooth[i], state.spectrum[i])
		}
	}

	return true
}

@private
Wavebar_Window :: struct {
	using base: Window_Base,
	calc_thread: ^thread.Thread,
	calc_state: analysis.Calc_Peaks_State,
	dec: decoder.Decoder,
	// The length of this array corresponds to the resolution of the output waveform
	output: [1080]f32,
	track_id: Track_ID,
}

_calc_wave_thread_proc :: proc(thread_data: ^thread.Thread) {
	state := cast(^Wavebar_Window) thread_data.data
	analysis.calc_peaks_over_time(&state.dec, state.output[:], &state.calc_state)
}

@private
WAVEBAR_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Wave Bar",
	internal_name = WINDOW_WAVEBAR,
	make_instance = wavebar_window_make_instance_proc,
	show = wavebar_window_show_proc,
	free = wavebar_window_free_proc,
}

@private
wavebar_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Wavebar_Window, allocator)
}

@private
wavebar_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	wavebar_window_show(sv, auto_cast self)
}

@private
wavebar_window_free_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
}

@private
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
			path := server.library_get_track_path(sv.library, path_buf[:], state.track_id) or_return
			decoder.open(&state.dec, path, nil) or_return

			ok = true

			thread.start(state.calc_thread)
		}
	}

	if state.track_id == 0 {return}

	position := f32(server.get_track_second(sv))
	duration := f32(server.get_track_duration_seconds(sv))

	if imx.wave_seek_bar("##waveform", state.output[:], &position, duration) {
		server.seek_to_second(sv, int(position))
	}

	return true
}

@private
show_spectrum_window :: proc(client: ^Client, state: ^Analysis_State) {
	band_colors: [SPECTRUM_MAX_BANDS]imgui.Vec4

	state.need_update_spectrum = true
	settings := &client.settings

	if settings.spectrum_bands == 0 {settings.spectrum_bands = 10}

	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Band count")
		if imgui.MenuItem("10", nil, settings.spectrum_bands == 10) {settings.spectrum_bands = 10}
		if imgui.MenuItem("20", nil, settings.spectrum_bands == 20) {settings.spectrum_bands = 20}
		if imgui.MenuItem("40", nil, settings.spectrum_bands == 40) {settings.spectrum_bands = 40}
		if imgui.MenuItem("60", nil, settings.spectrum_bands == 60) {settings.spectrum_bands = 60}
		if imgui.MenuItem("80", nil, settings.spectrum_bands == 80) {settings.spectrum_bands = 80}

		imgui.SeparatorText("Display mode")
		if imgui.MenuItem("Bars", nil, settings.spectrum_mode == .Bars) {
			settings.spectrum_mode = .Bars
		}
		if imgui.MenuItem("Alpha", nil, settings.spectrum_mode == .Alpha) {
			settings.spectrum_mode = .Alpha
		}
		if imgui.MenuItem("Line", nil, settings.spectrum_mode == .Line) {
			settings.spectrum_mode = .Line
		}

		imgui.SeparatorText("Display settings")
		imgui.MenuItemBoolPtr("Show slow peaks", nil, &settings.spectrum_show_slow_peaks)

		imgui.EndPopup()
	}


	spectrum := state.spectrum[:settings.spectrum_bands]

	drawlist := imgui.GetWindowDrawList()
	theme := &global_theme

	// Calculate band colors
	{
		quiet_color := theme.custom_colors[.PeakQuiet]
		loud_color := theme.custom_colors[.PeakLoud]

		for band, index in spectrum {
			band_colors[index] = glm.lerp(quiet_color, loud_color, band)
		}
	}

	if settings.spectrum_mode != .Line {
		imgui.PushStyleColor(.TableHeaderBg, 0)
		defer imgui.PopStyleColor()

		imgui.PushStyleVarImVec2(.CellPadding, {})
		defer imgui.PopStyleVar()

		imgui.PushStyleVar(.TableAngledHeadersAngle, math.to_radians_f32(20))
		defer imgui.PopStyleVar()

		imgui.PushStyleVarImVec2(.TableAngledHeadersTextAlign, {0.5, 0.5})
		defer imgui.PopStyleVar()
		
		color_negative :: proc(color: imgui.Vec4) -> imgui.Vec4 {
			return {1, 1, 1, 1} - color
		}

		table_flags := imgui.TableFlags_BordersInner
		if imgui.BeginTable("##spectrum_table", auto_cast settings.spectrum_bands, table_flags) {
			for &str in state.spectrum_frequency_strings[:settings.spectrum_bands] {
				imgui.TableSetupColumn(cstring(&str[0]), {.AngledHeader})
			}
			
			imgui.TableAngledHeadersRow()
			
			imgui.TableNextRow()
			for band, band_index in spectrum {
				if imgui.TableNextColumn() {
					size := imgui.GetContentRegionAvail()
					cursor := imgui.GetCursorScreenPos()
					color := band_colors[band_index]
					
					if settings.spectrum_mode == .Bars {
						imgui.DrawList_AddRectFilled(drawlist, 
							{cursor.x, cursor.y + size.y}, 
							{cursor.x + size.x, cursor.y + size.y * (1 - band)},
							imgui.GetColorU32ImVec4(color),
						)
					}
					else if settings.spectrum_mode == .Alpha {
						color.a *= band
						imgui.DrawList_AddRectFilled(drawlist, 
							cursor,
							cursor + size,
							imgui.GetColorU32ImVec4(color),
						)
					}
				}
			}

			// Slow peaks
			if settings.spectrum_show_slow_peaks && imgui.TableSetColumnIndex(0) {
				for band, band_index in state.spectrum_smooth[:settings.spectrum_bands] {
					color := color_negative(band_colors[band_index])
					color.a = 1

					cursor := imgui.GetCursorScreenPos()
					size := imgui.GetContentRegionAvail()
					y := cursor.y + (size.y * (1 - band))

					imgui.DrawList_AddLine(drawlist, 
						{cursor.x, y}, 
						{cursor.x + size.x, y},
						imgui.GetColorU32ImVec4(color),
						2
					)

					if !imgui.TableNextColumn() {break}
				}
			}

			imgui.EndTable()
		}
	}
	else {
		band_positions: [SPECTRUM_MAX_BANDS]imgui.Vec2
		cursor := imgui.GetCursorScreenPos()
		size := imgui.GetContentRegionAvail()
		gap := size.x / f32(settings.spectrum_bands)

		cursor.y += size.y

		band_positions[0] = {
			cursor.x,
			cursor.y - (state.spectrum[0] * size.y),
		}

		for index in 1..<settings.spectrum_bands {
			band := state.spectrum[index]
			band_positions[index] = {
				cursor.x + (gap * f32(index)),
				cursor.y - (band * size.y),
			}

			imgui.DrawList_AddLine(
				drawlist,
				band_positions[index-1],
				band_positions[index],
				imgui.GetColorU32ImVec4(band_colors[index])
			)
		}

		
	}
}

@private
Oscilloscope_Channel_Mode :: enum {
	Mono,
	Separate,
	Overlapped,
}

@private
Oscilloscope_Window :: struct {
	using base: Window_Base,
	sample_count: int,
	window_w: [dynamic]f32,
	channel_mode: Oscilloscope_Channel_Mode,
}

@private
OSCILLOSCOPE_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Oscilloscope",
	internal_name = WINDOW_OSCILLOSCOPE,
	make_instance = oscilloscope_window_make_instance_proc,
	save_config = oscilloscope_window_save_config_proc,
	configure = oscilloscope_window_configure_proc,
	show = oscilloscope_window_show_proc,
	free = oscilloscope_window_free_proc,
	flags = {.MultiInstance},
}

@private
oscilloscope_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Oscilloscope_Window, allocator)
}

@private
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

@private
oscilloscope_window_save_config_proc :: proc(self: ^Window_Base, out_buf: ^imgui.TextBuffer) {
	state := cast(^Oscilloscope_Window) self
	channel_mode_buf: [64]u8
	copy(channel_mode_buf[:63], reflect.enum_name_from_value(state.channel_mode) or_else "")

	imgui.TextBuffer_appendf(out_buf, "Resolution=%d\n", i32(state.sample_count))
	imgui.TextBuffer_appendf(out_buf, "ChannelMode=%s\n", cstring(&channel_mode_buf[0]))
}

@private
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

@private
oscilloscope_window_free_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Oscilloscope_Window) self
	delete(state.window_w)
	state.window_w = nil
}

@private
show_oscilloscope_window :: proc(client: ^Client) {
	state := &client.analysis
	state.need_update_osc = true
	if state.osc_length == 0 || len(state.osc_window) != state.osc_length {return}
	size := imgui.GetContentRegionAvail()

	color := imgui.GetColorU32(.PlotLines)
	drawlist := imgui.GetWindowDrawList()
	gap := size.x / f32(state.osc_length)
	y_off := size.y * 0.5
	cursor := imgui.GetCursorScreenPos()

	for i in 0..<(state.osc_length-1) {
		a := clamp(state.osc_input[0][i] * state.osc_window[i], -1, 1)*0.5
		b := clamp(state.osc_input[0][i+1] * state.osc_window[i+1], -1, 1)*0.5
		p1 := cursor + {f32(i) * gap, y_off + size.y * a}
		p2 := cursor + {f32(i+1) * gap, y_off + size.y * b}
		imgui.DrawList_AddLine(drawlist, p1, p2, color)
	}

	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Samples")
		if imgui.MenuItem("128") {state.osc_length = 128}
		if imgui.MenuItem("256") {state.osc_length = 256}
		if imgui.MenuItem("512") {state.osc_length = 512}
		if imgui.MenuItem("1024") {state.osc_length = 1024}
		if imgui.MenuItem("2048") {state.osc_length = 2048}
		if imgui.MenuItem("4096") {state.osc_length = 4096}
		imgui.EndPopup()
	}
}

@private
Spectrum_Display_Mode :: enum {
	Bars,
	Alpha,
	Line,
}

Spectrum_Band_Distribution :: enum {
	Uniform,
	Natural,
}

@private
Spectrum_Window :: struct {
	using base: Window_Base,
	band_freqs: [SPECTRUM_MAX_BANDS]f32,
	band_heights: [SPECTRUM_MAX_BANDS]f32,
	band_freqs_calculated: int,
	band_count: int,
	display_mode: Spectrum_Display_Mode,
	band_distribution: Spectrum_Band_Distribution,
	band_scaling_factor: f32,
	interpolation_speed: f32,
	should_interpolate: bool,
}

@private
SPECTRUM_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Spectrum",
	internal_name = WINDOW_SPECTRUM,
	configure = spectrum_window_configure_proc,
	save_config = spectrum_window_save_config_proc,
	make_instance = spectrum_window_make_instance_proc,
	show = spectrum_window_show_proc,
	free = spectrum_window_free_proc,
	flags = {.MultiInstance},
}

@private
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

@private
spectrum_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	ret := new(Spectrum_Window, allocator)
	ret.band_scaling_factor = 2.5
	ret.interpolation_speed = 30
	return ret
}

@private
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

@private
spectrum_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Spectrum_Window) self
	real_band_heights: [SPECTRUM_MAX_BANDS]f32
	band_colors: [SPECTRUM_MAX_BANDS]u32

	if state.band_count <= 10 || state.band_count > SPECTRUM_MAX_BANDS {state.band_count = SPECTRUM_MAX_BANDS}

	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Display mode")
		if imgui.MenuItem("Bar graph", nil, state.display_mode == .Bars) {state.display_mode = .Bars}
		if imgui.MenuItem("Alpha", nil, state.display_mode == .Alpha) {state.display_mode = .Alpha}
		//if imgui.MenuItem("Line", nil, state.display_mode == .Line) {state.display_mode = .Line}
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
		band_colors: []u32,
		band_distribution: Spectrum_Band_Distribution,
		band_scaling_factor: f32,
	) {
		band_width: [SPECTRUM_MAX_BANDS]f32
		x_offset: f32 = 0

		distribute_band_widths(size.x, band_width[:len(bands)], band_distribution, band_scaling_factor)

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
			assert(i >= 0)
		}
	}

	draw_spectrum_fading_bars :: proc(
		drawlist: ^imgui.DrawList,
		pos: imgui.Vec2, size: imgui.Vec2, bands: []f32,
		band_colors: []u32,
		band_distribution: Spectrum_Band_Distribution,
		band_scaling_factor: f32,
	) {
		band_width: [SPECTRUM_MAX_BANDS]f32
		x_offset: f32 = 0

		distribute_band_widths(size.x, band_width[:len(bands)], band_distribution, band_scaling_factor)

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
			assert(i >= 0)
		}
	}

	switch state.display_mode {
		case .Bars: {
			draw_spectrum_bar_graph(
				drawlist, imgui.GetCursorScreenPos(),
				imgui.GetContentRegionAvail(),
				state.band_heights[:state.band_count],
				band_colors[:state.band_count],
				state.band_distribution,
				state.band_scaling_factor,
			)
		}
		case .Alpha: {
			draw_spectrum_fading_bars(
				drawlist, imgui.GetCursorScreenPos(),
				imgui.GetContentRegionAvail(),
				state.band_heights[:state.band_count],
				band_colors[:state.band_count],
				state.band_distribution,
				state.band_scaling_factor,
			)
		}
		case .Line: {
		}
	}
}

@private
spectrum_window_free_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
}

