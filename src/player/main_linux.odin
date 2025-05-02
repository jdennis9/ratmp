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
package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:os/os2"
import "core:path/filepath"
import "vendor:glfw"

import imgui "libs:odin-imgui"

import com "player:main_common"
import "player:build"
import video "player:video/opengl"
import "player:library"
import "player:config"
import "player:util"

foreign import cpp "../cpp/cpp.a"

foreign cpp {
	init_gtk :: proc() ---
}

state: com.State

this: struct {
	ctx: runtime.Context,
	window: glfw.WindowHandle,
	running: bool,
	window_title_track_id: library.Track_ID,
	close_policy: config.Close_Policy,
}

handle_tray_icon_message :: proc "c" (message: c.int) {
	TRAY_SIGNAL_CLICK :: 0
	TRAY_SIGNAL_EXIT :: 1

	if message == TRAY_SIGNAL_CLICK {
		glfw.ShowWindow(this.window)
	}
	else {
		this.running = false
	}
}

handle_window_close :: proc "c" (window: glfw.WindowHandle) {
	context = this.ctx

	switch this.close_policy {
		case .Exit: {
			this.running = false
			log.debug("Exiting from window close...")
		}
		case .AlwaysAsk: {
			if util.message_box("", .YesNo, "Keep running in background?") {
				glfw.IconifyWindow(window)
				glfw.HideWindow(window)
			}
			else {
				this.running = false
			}
		}
		case .MinimizeToTray: {
			// @TODO: Add to system tray
			glfw.IconifyWindow(window)
		}
	}
}

wake_proc :: proc() {
	glfw.PostEmptyEvent()
}

run :: proc() -> bool {
	context.logger = log.create_console_logger()
	this.ctx = context

	init_gtk()
	glfw.Init() or_return

	this.window = glfw.CreateWindow(800, 800, build.PROGRAM_NAME_AND_VERSION, nil, nil)
	if this.window == nil {return false}
	defer glfw.DestroyWindow(this.window)

	glfw.SetWindowCloseCallback(this.window, handle_window_close)

	imgui.CreateContext()
	defer imgui.DestroyContext()
	
	video.init_for_linux(this.window) or_return
	defer video.shutdown()

	com.init(&state, find_config_dir(), find_data_dir(), wake_proc)
	defer com.shutdown()

	this.running = true

	for this.running {
		glfw.PollEvents()

		if this.running == false {break}

		// Apply preferences
		if state.prefs.dirty {
			this.close_policy = state.prefs.values.close_policy
		}

		com.handle_events()

		// Update window title
		if this.window_title_track_id != state.playback.playing_track {
			title_buf: [256]u8
			this.window_title_track_id = state.playback.playing_track
			track := library.get_track_info(state.library, state.playback.playing_track)

			title := fmt.bprint(
				title_buf[:len(title_buf)-1],
				build.PROGRAM_NAME_AND_VERSION, "|", track.artist, "-", track.title
			)

			glfw.SetWindowTitle(this.window, cstring(&title_buf[0]))
		}

		if video.begin_frame() {
			this.running = com.frame()
			video.end_frame()
		}
	}

	return true
}

main :: proc() {
	run()
}

find_data_dir :: proc(allocator := context.allocator) -> string {
	home := os2.get_env("HOME", allocator)
	defer delete(home)

	when ODIN_DEBUG {
		return strings.clone(".", allocator)
	}
	else {
		path := filepath.join({home, ".local/share/zno"}, allocator)
		if !os2.exists(path) {
			os2.make_directory_all(path)
		}
		return path
	}
}

find_config_dir :: proc(allocator := context.allocator) -> string {
	home := os2.get_env("HOME", allocator)
	defer delete(home)

	when ODIN_DEBUG {
		return strings.clone(".", allocator)
	}
	else {
		config_dir, have_config_dir := os2.lookup_env("XDG_CONFIG_HOME", allocator)
		if have_config_dir {
			path := filepath.join({config_dir, "zno"}, allocator)
			if !os2.exists(path) {os2.make_directory_all(path)}
			delete(config_dir)
			return path
		}
		else {
			path := filepath.join({home, ".config/zno"}, allocator)
			if !os2.exists(path) {os2.make_directory_all(path)}
			return path
		}
	}
}
