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

import imgui "libs:odin-imgui"

import "player:system_paths"
import "player:config"
import "player:theme"
import "player:library"
import "player:ui"
import "player:video"
import "player:playback"
import "player:audio"

LIBRARY_PATH :: "library.json"
CONFIG_PATH :: "config.ini"

State :: struct {
	ctx: runtime.Context,
	library: library.Library,
	ui: ui.State,
	playback_decoder_lock: sync.Mutex,
	playback: playback.State,
	audio_stream_info: audio.Stream_Info,
	prefs: config.Preferences,

	// Paths
	library_path: string,
	config_path: string,

	playback_eof: bool,
	wake_proc: proc(),
}

// Held by entry point
state: ^State

audio_callback :: proc(buffer: []f32, data: rawptr) {
	sync.lock(&state.playback_decoder_lock)
	defer sync.unlock(&state.playback_decoder_lock)

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
	state.config_path = filepath.join({config_dir, "config.ini"})
	state.library_path = filepath.join({data_dir, "library.json"})
	state.wake_proc = wake_proc

	system_paths.init()
	audio.init() or_return
	state.library = library.load_library(state.library_path, "playlists") or_return
	state.playback = playback.init() or_return
	state.prefs, _ = config.load("config.ini")
	theme.init(state.prefs)
	playback.init()
	state.ui = ui.init() or_return
	ui.install_imgui_settings_handler(&state.ui)

	// Start audio stream
	{
		device_id := audio.get_default_device_id() or_return
		state.audio_stream_info = audio.start(&device_id, audio_callback, nil) or_return
	}

	ui.apply_prefs(&state.ui, &state.prefs)

	return true
}

handle_events :: proc() {
	if state.prefs.dirty {
		ui.apply_prefs(&state.ui, &state.prefs)
		state.prefs.dirty = false
	}

	if state.playback_eof {
		playback.play_next_track(&state.playback, state.library)
	}
}

frame :: proc() -> bool {
	return ui.show(&state.ui, &state.library, &state.playback, &state.prefs)
}

shutdown :: proc() {
	config.save(state.prefs, state.config_path)
	ui.destroy(state.ui)
	playback.destroy(&state.playback)
	audio.shutdown()
	library.save_to_file(state.library, LIBRARY_PATH)
	library.destroy(state.library)
}
