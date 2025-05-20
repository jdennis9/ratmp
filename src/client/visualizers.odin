#+private file
package client

import "core:thread"
import "core:math"
import "core:fmt"
import "core:strings"
import glm "core:math/linalg/glsl"
import "core:time"

import imgui "src:thirdparty/odin-imgui"

import "src:analysis"
import "src:decoder"
import "src:server"

PEAK_ROUGHNESS :: 20
SECONDARY_PEAK_ROUGHNESS :: 1
WINDOW_SIZE :: 8192
MAX_SPECTRUM_BAND_COUNT :: 80
MAX_OSCILLOSCOPE_SAMPLES :: 4096

@private
_Spectrum_Display_Mode :: enum {
	Bars,
	Alpha,
}

@private
_Analysis_State :: struct {
	channels, samplerate: int,

	peaks: [server.MAX_OUTPUT_CHANNELS]f32,
	need_update_peaks: bool,

	window_w: [WINDOW_SIZE]f32,
	window_data: [server.MAX_OUTPUT_CHANNELS][WINDOW_SIZE]f32,
	
	spectrum_analyzer: analysis.Spectrum_Analyzer,
	spectrum_frequencies: [MAX_SPECTRUM_BAND_COUNT]f32,
	spectrum_frequency_bands_calculated: int,
	spectrum: [MAX_SPECTRUM_BAND_COUNT]f32,
	spectrum_bands: int,
	spectrum_display_mode: _Spectrum_Display_Mode,
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
_analysis_init :: proc(state: ^_Analysis_State) {
	window_sum: f32
	state.spectrum_bands = 40
	state.osc_length = MAX_OSCILLOSCOPE_SAMPLES

	// Hann window
	_hann_window(state.window_w[:])

	analysis.spectrum_analyzer_init(&state.spectrum_analyzer, WINDOW_SIZE, 1/window_sum)
}

@private
_analysis_destroy :: proc(state: ^_Analysis_State) {
	analysis.spectrum_analyzer_destroy(&state.spectrum_analyzer)
	delete(state.osc_window)
}

@private
_update_analysis :: proc(cl: ^Client, sv: ^Server, delta: f32) -> bool {
	state := &cl.analysis
	tick := cl.tick_last_frame

	if server.is_paused(sv^) {return false}

	state.samplerate, state.channels = server.audio_time_frame_from_playback(sv, state.window_data[:], tick, delta) or_return

	// Blackman window
	/*for &f, i in window.data[0] {
		n := f32(i)
		N := f32(len(window.data[0]))
		a0 :: 0.42
		a1 :: 0.5
		a2 :: 0.08
		t0 := (2*math.PI*n)/N
		t1 := (4*math.PI*n)/N
		w := a0 - (a1*math.cos(t0)) + (a2*math.cos(t1))
		f *= w
	}*/

	t := clamp(PEAK_ROUGHNESS*delta, 0, 1)
	//t := PEAK_ROUGHNESS*delta

	// Peak
	peaks: [server.MAX_OUTPUT_CHANNELS]f32
	if state.need_update_peaks {
		state.need_update_peaks = false
		for ch in 0..<state.channels {
			peak := analysis.calc_peak(state.window_data[ch][:1024])
			state.peaks[ch] = math.lerp(state.peaks[ch], peak, t)
		}
	}

	// Oscilloscope
	if state.need_update_osc {
		if state.osc_length == 0 {state.osc_length = 4096}
		if len(state.osc_window) != state.osc_length {
			resize(&state.osc_window, state.osc_length)
			_osc_window(state.osc_window[:])
		}
		state.need_update_osc = false
		state.samplerate, state.channels, _ = server.audio_time_frame_from_playback(sv, state.osc_input[:], tick, 0)
	}

	// Apply window multipliers
	for ch in 0..<1 {
		for &f, i in state.window_data[ch] {
			f *= state.window_w[i]
		}
	}

	// Spectrum
	spectrum: [MAX_SPECTRUM_BAND_COUNT]f32
	if state.need_update_spectrum {
		if state.spectrum_bands == 0 || state.spectrum_bands != state.spectrum_frequency_bands_calculated {
			state.spectrum_frequency_bands_calculated = state.spectrum_bands
			analysis.calc_spectrum_frequencies(state.spectrum_frequencies[:state.spectrum_bands])
		}

		state.need_update_spectrum = false
		analysis.spectrum_analyzer_calc(
			&state.spectrum_analyzer,
			state.window_data[0][:],
			state.spectrum_frequencies[:],
			spectrum[:],
			f32(state.samplerate)
		)

		for f, i in spectrum {
			state.spectrum[i] = math.lerp(state.spectrum[i], f, t)
		}
	}

	return true
}

@private
_Waveform_Window :: struct {
	calc_thread: ^thread.Thread,
	calc_state: analysis.Calc_Peaks_State,
	dec: decoder.Decoder,
	// The length of this array corresponds to the resolution of the output waveform
	output: [1080]f32,
	track_id: Track_ID,
}

_calc_wave_thread_proc :: proc(thread_data: ^thread.Thread) {
	state := cast(^_Waveform_Window) thread_data.data
	analysis.calc_peaks_over_time(&state.dec, state.output[:], &state.calc_state)
}

@private
_show_waveform_window :: proc(sv: ^Server, state: ^_Waveform_Window) -> (ok: bool) {
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
			decoder.open(&state.dec, path) or_return

			ok = true

			thread.start(state.calc_thread)
		}
	}

	if state.track_id == 0 {return}

	position := f32(server.get_track_second(sv))
	duration := f32(server.get_track_duration_seconds(sv))

	if _waveform_seek_bar("##waveform", state.output[:], &position, duration) {
		server.seek_to_second(sv, int(position))
	}

	return true
}

@private
_show_spectrum_window :: proc(client: ^Client, state: ^_Analysis_State) {
	state.need_update_spectrum = true

	if state.spectrum_bands == 0 {return}

	spectrum := state.spectrum[:state.spectrum_bands]

	drawlist := imgui.GetWindowDrawList()
	theme := &client.theme

	imgui.PushStyleColor(.TableHeaderBg, 0)
	defer imgui.PopStyleColor()

	imgui.PushStyleVarImVec2(.CellPadding, {})
	defer imgui.PopStyleVar()

	imgui.PushStyleVar(.TableAngledHeadersAngle, math.to_radians_f32(20))
	defer imgui.PopStyleVar()

	imgui.PushStyleVarImVec2(.TableAngledHeadersTextAlign, {0.5, 0.5})
	defer imgui.PopStyleVar()
	
	if imgui.BeginPopupContextWindow() {
		imgui.SeparatorText("Band count")
		if imgui.MenuItem("10", nil, state.spectrum_bands == 10) {state.spectrum_bands = 10}
		if imgui.MenuItem("20", nil, state.spectrum_bands == 20) {state.spectrum_bands = 20}
		if imgui.MenuItem("40", nil, state.spectrum_bands == 40) {state.spectrum_bands = 40}
		if imgui.MenuItem("60", nil, state.spectrum_bands == 60) {state.spectrum_bands = 60}
		if imgui.MenuItem("80", nil, state.spectrum_bands == 80) {state.spectrum_bands = 80}

		imgui.SeparatorText("Display mode")
		if imgui.MenuItem("Bars", nil, state.spectrum_display_mode == .Bars) {
			state.spectrum_display_mode = .Bars
		}
		if imgui.MenuItem("Alpha", nil, state.spectrum_display_mode == .Alpha) {
			state.spectrum_display_mode = .Alpha
		}
		imgui.EndPopup()
	}

	table_flags := imgui.TableFlags_BordersInner
	if imgui.BeginTable("##spectrum_table", auto_cast state.spectrum_bands, table_flags) {
		for band in state.spectrum_frequencies[:state.spectrum_bands] {
			buf: [32]u8
			name: string
			if band > 10000 {
				name = fmt.bprintf(buf[:31], "%dK", int(f32(math.round(band))/1000))
			}
			else if band > 1000 {
				name = fmt.bprintf(buf[:31], "%1.1fK", f32(math.round(band))/1000)
			}
			else {
				name = fmt.bprintf(buf[:31], "%g", math.round(band))
			}
			imgui.TableSetupColumn(strings.unsafe_string_to_cstring(name), {.AngledHeader})
		}
		
		imgui.TableAngledHeadersRow()
		
		imgui.TableNextRow()
		for unclamped_band in spectrum {
			band := clamp(unclamped_band, 0, 1)

			if imgui.TableNextColumn() {
				size := imgui.GetContentRegionAvail()
				cursor := imgui.GetCursorScreenPos()

				quiet_color := theme.custom_colors[.PeakQuiet]
				loud_color := theme.custom_colors[.PeakLoud]
				color := glm.lerp(quiet_color, loud_color, band)
				
				if state.spectrum_display_mode == .Bars {
					imgui.DrawList_AddRectFilled(drawlist, 
						{cursor.x, cursor.y + size.y}, 
						{cursor.x + size.x, cursor.y + size.y * (1 - band)},
						imgui.GetColorU32ImVec4(color),
					)
				}
				else if state.spectrum_display_mode == .Alpha {
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
		/*if imgui.TableSetColumnIndex(0) {
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
		}*/

		imgui.EndTable()
	}
}

@private
_show_oscilloscope_window :: proc(client: ^Client) {
	state := &client.analysis
	state.need_update_osc = true
	if state.osc_length == 0 || len(state.osc_window) != state.osc_length {return}
	size := imgui.GetContentRegionAvail()
	//imgui.PlotLines("##osc", &state.osc_input[0][0], auto_cast state.osc_length, 0, nil, -1, 1, size)
	//imgui.PlotHistogram("##osc", &state.osc_input[0][0], auto_cast state.osc_length, 0, nil, 0, 1, size)

	color := imgui.GetColorU32(.PlotLines)
	drawlist := imgui.GetWindowDrawList()
	gap := size.x / f32(state.osc_length)
	y_off := size.y * 0.5
	cursor := imgui.GetCursorScreenPos()

	for i in 0..<(state.osc_length-1) {
		a := clamp(state.osc_input[0][i] * state.osc_window[i], -1, 1)
		b := clamp(state.osc_input[0][i+1] * state.osc_window[i+1], -1, 1)
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
