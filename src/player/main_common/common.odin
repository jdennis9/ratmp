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
package main_common

import "base:runtime"
import "core:path/filepath"

import "player:config"
import "player:theme"
import "player:library"
import "player:ui"
import "player:playback"
import "player:audio"
import "player:util"

State :: struct {
	ctx: runtime.Context,
	library: library.Library,
	ui: ui.State,
	playback: playback.State,
	stream: ^audio.Stream,
	prefs: config.Preference_Manager,
	saved_state: config.Saved_State,

	// Paths
	library_path: string,
	config_path: string,
	saved_state_path: string,

	playback_eof: bool,
	wake_proc: proc(),

	current_audio_device_id: audio.Device_ID,
	frame_index: int,
}

// Held by entry point
state: ^State

audio_callback :: proc(_: rawptr, buffer: []f32) {
	context = state.ctx

	state.playback_eof = playback.stream(
		&state.playback, buffer,
		state.stream.samplerate, state.stream.channels
	)
	
	if state.playback_eof {
		if state.wake_proc != nil {state.wake_proc()}
	}
}

init :: proc(state_ptr: ^State, config_dir: string, data_dir: string, wake_proc: proc()) -> bool {
	state = state_ptr
	state.ctx = context
	state.config_path = filepath.join({config_dir, "preferences.json"})
	state.library_path = filepath.join({data_dir, "library.json"})
	state.saved_state_path = filepath.join({data_dir, "state.json"})
	state.wake_proc = wake_proc

	// Config
	state.prefs = config.init_preferences()
	config.load_preferences(&state.prefs, state.config_path)
	state.saved_state, _ = config.load_state(state.saved_state_path)

	// Library
	state.library = library.init(filepath.join({data_dir, "playlists"}, context.temp_allocator))
	library.load(&state.library, state.library_path)

	// Playback
	state.playback = playback.init() or_return
	playback.set_shuffle_enabled(&state.playback, state.saved_state.shuffle_enabled)

	// UI
	theme.init(state.prefs.values, filepath.join({config_dir, "themes"}, context.temp_allocator))
	state.ui = ui.init(data_dir, state.saved_state) or_return
	ui.install_imgui_settings_handler(&state.ui)
	
	// Start audio stream
	{
		audio.init() or_return
		device_id := _get_preferred_audio_device_id()
		state.current_audio_device_id = device_id
		state.stream = audio.open_stream(&device_id, audio_callback, nil) or_return
	}

	ui.apply_prefs(&state.ui, state.prefs.values)

	return true
}

interrupt_audio_once_this_frame :: proc() {
	@static frame_index: int

	if frame_index != state.frame_index {
		audio.stream_interrupt(state.stream)
		frame_index = state.frame_index
	}
}

handle_events :: proc() {
	@static playing_track: library.Track_ID
	@static paused: bool = false

	if state.playback.paused != paused {
		paused = state.playback.paused
		interrupt_audio_once_this_frame()
	}

	if state.playback.playing_track != playing_track {
		playing_track = state.playback.playing_track
		interrupt_audio_once_this_frame()
	}

	if state.prefs.dirty {
		prefs := state.prefs.values
		ui.apply_prefs(&state.ui, prefs)

		if prefs.audio_device_id != "" && prefs.audio_device_id != string(cstring(&state.current_audio_device_id[0])) {
			stream_ok: bool
			device_id := _get_preferred_audio_device_id()
			audio.close_stream(state.stream)
			state.stream, stream_ok = audio.open_stream(&device_id, audio_callback, nil)

			if !stream_ok {
				default_device_id, have_default := audio.get_default_device_id()
				if have_default {
					state.stream, _ = audio.open_stream(&default_device_id, audio_callback, nil)
				}
			}
		}

		state.prefs.dirty = false
	}
	
	if state.playback_eof {
		state.playback_eof = false
		playback.play_next_track(&state.playback, state.library)
		interrupt_audio_once_this_frame()
	}

	state.frame_index += 1
}

frame :: proc() -> (keep_running: bool, minimize_to_tray: bool) {
	saved_state_before := state.saved_state

	keep_running, minimize_to_tray = ui.show(&state.ui, &state.library, &state.playback, &state.prefs, state.stream)
	if !keep_running {return false, false}

	// Update saved state
	state.saved_state.prefer_peak_meter_in_menu_bar = state.ui.prefer_peak_meter_in_menu_bar
	state.saved_state.shuffle_enabled = state.playback.shuffle

	if state.saved_state != saved_state_before {
		config.save_state(state.saved_state, state.saved_state_path)
	}

	return
}

shutdown :: proc() {
	config.save_preferences(state.prefs, state.config_path)
	config.save_state(state.saved_state, state.saved_state_path)
	ui.destroy(state.ui)
	playback.destroy(&state.playback)
	audio.shutdown()
	library.save_to_file(state.library, state.library_path)
	library.destroy(state.library)
}

@private
_get_preferred_audio_device_id :: proc() -> audio.Device_ID {
	prefs_id: audio.Device_ID
	default_id := audio.get_default_device_id() or_else audio.Device_ID{}
	util.copy_string_to_buf(prefs_id[:], state.prefs.values.audio_device_id)
	return prefs_id[0] != 0 ? prefs_id : default_id
}
