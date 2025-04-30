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

import imgui "libs:odin-imgui"

import "player:system_paths"
import "player:prefs"
import "player:theme"
import "player:library"
import "player:ui"
import "player:video"
import "player:playback"
import "player:signal"
import "player:audio"

state: struct {
	ctx: runtime.Context,
	library: library.Library,
	ui: ui.State,
	playback_decoder_lock: sync.Mutex,
	playback: playback.State,
	audio_stream_info: audio.Stream_Info,
}

audio_callback :: proc(buffer: []f32, data: rawptr) {
	sync.lock(&state.playback_decoder_lock)
	defer sync.unlock(&state.playback_decoder_lock)

	context = state.ctx

	playback.stream(&state.playback, buffer, cast(int) state.audio_stream_info.sample_rate, cast(int) state.audio_stream_info.channels)
}

init :: proc() -> bool {
	audio.init() or_return
	state.library = library.load_library("library.json", "playlists") or_return
	state.playback = playback.init() or_return
	system_paths.init()
	prefs.load()
	theme.init()
	playback.init()
	state.ui = ui.init() or_return
	ui.install_imgui_settings_handler(&state.ui)

	// Start audio stream
	{
		device_id := audio.get_default_device_id() or_return
		state.audio_stream_info = audio.start(&device_id, audio_callback, nil) or_return
	}

	return true
}

frame :: proc() {
	signal.post(.NewFrame)
	ui.show(&state.ui, &state.library, &state.playback)
}

shutdown :: proc() {
	prefs.save()
	ui.destroy(state.ui)
	playback.destroy(&state.playback)
	audio.shutdown()
	library.destroy(state.library)
}
