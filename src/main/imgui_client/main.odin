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
package client

import "core:log"
import "src:main/media_controls"
import "core:os"
import "core:flags"
import "src:main/shared"
import lib "src:main/library"
import "src:main/player"
import imgui "src:thirdparty/odin-imgui"

launch_config: struct {
	no_media_controls: bool `usage:"Disable system media controls."`,
	headless:          bool `usage:"Run without UI."`,
	memory_debug:      bool `usage:"[Debug] Track memory usage."`,
	no_audio:          bool `usage:"[Debug] Disable audio output."`,
}


@(private="file")
run :: proc() -> shared.Error {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	flags.parse_or_exit(&launch_config, os.args)

	lib.init({
		enable_memory_tracking = launch_config.memory_debug,
	}) or_return
	defer lib.shutdown()

	player.init({
		no_audio = launch_config.no_audio,
	}) or_return
	defer player.shutdown()

	imgui.CreateContext()
	defer imgui.DestroyContext()

	if io := imgui.GetIO(); io != nil {
		io.ConfigFlags |= {.DockingEnable}
	}

	if !launch_config.no_media_controls {
		when ODIN_OS == .Windows do media_controls.init_smtc()
	}

	if !launch_config.headless {
		when ODIN_OS == .Windows do platform_init_win32() or_return
		else do platform_init_glfw() or_return
	}

	platform_make_window() or_return
	defer platform_destroy_window()

	ui_init() or_return
	defer ui_shutdown()

	for {
		platform_poll_events()
		
		platform_imgui_new_frame()
		video_imgui_new_frame()
		imgui.NewFrame()
		
		ui_show()

		imgui.Render()

		video_render_frame()
	}

	return nil
}

main :: proc() {
	run()
}


