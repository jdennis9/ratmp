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
import "core:sync"
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
	audio_stream_info: audio.Stream_Info,
	prefs: config.Preference_Manager,
	saved_state: config.Saved_State,

	// Paths
	library_path: string,
	config_path: string,
	saved_state_path: string,

	playback_eof: bool,
	wake_proc: proc(),

	current_audio_device_id: audio.Device_ID,
}

// Held by entry point
state: ^State

audio_callback :: proc(buffer: []f32, data: rawptr) {
	sync.lock(&state.playback.lock)
	defer sync.unlock(&state.playback.lock)

	context = state.ctx

	state.playback_eof = playback.stream(
		&state.playback, buffer, cast(int) state.audio_stream_info.sample_rate,
		cast(int) state.audio_stream_info.channels)
	
	if state.playback_eof {
		if state.wake_proc != nil {state.wake_proc()}
	}
}

init :: proc(state_ptr: ^State, config_dir: string, data_dir: string, wake_proc: proc()) -> bool {
	state = state_ptr
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
		state.audio_stream_info = audio.start(&device_id, audio_callback, nil) or_return
	}

	ui.apply_prefs(&state.ui, state.prefs.values)

	return true
}

handle_events :: proc() {
	if state.prefs.dirty {
		prefs := state.prefs.values
		ui.apply_prefs(&state.ui, prefs)

		if prefs.audio_device_id != "" && prefs.audio_device_id != string(cstring(&state.current_audio_device_id[0])) {
			stream_ok: bool
			device_id := _get_preferred_audio_device_id()
			audio.stop()
			state.audio_stream_info, stream_ok = audio.start(&device_id, audio_callback, nil)

			if !stream_ok {
				default_device_id, have_default := audio.get_default_device_id()
				if have_default {
					state.audio_stream_info, _ = audio.start(&default_device_id, audio_callback, nil)
				}
			}
		}

		state.prefs.dirty = false
	}

	if state.playback_eof {
		playback.play_next_track(&state.playback, state.library)
	}
}

frame :: proc() -> bool {
	saved_state_before := state.saved_state

	ui.show(&state.ui, &state.library, &state.playback, &state.prefs) or_return

	// Update saved state
	state.saved_state.prefer_peak_meter_in_menu_bar = state.ui.prefer_peak_meter_in_menu_bar
	state.saved_state.shuffle_enabled = state.playback.shuffle

	if state.saved_state != saved_state_before {
		config.save_state(state.saved_state, state.saved_state_path)
	}

	return true
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
