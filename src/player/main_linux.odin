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

import "core:fmt"
import "core:log"
import "core:strings"
import "vendor:glfw"

import imgui "libs:odin-imgui"

import com "player:main_common"
import "player:build"
import video "player:video/opengl"
import "player:library"

state: com.State

this: struct {
	window: glfw.WindowHandle,
    running: bool,
    window_title_track_id: library.Track_ID,
}

wake_proc :: proc() {
    glfw.PostEmptyEvent()
}

run :: proc() -> bool {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger()
	}

	glfw.Init() or_return

    this.window = glfw.CreateWindow(800, 800, build.PROGRAM_NAME_AND_VERSION, nil, nil)
    if this.window == nil {return false}
    defer glfw.DestroyWindow(this.window)

    imgui.CreateContext()
    defer imgui.DestroyContext()
    
    video.init_for_linux(this.window) or_return
    defer video.shutdown()

    com.init(&state, ".", ".", wake_proc)
    defer com.shutdown()

    this.running = true

    for this.running {
        glfw.PollEvents()

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

