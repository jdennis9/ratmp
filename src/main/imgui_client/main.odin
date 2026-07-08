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

import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "src:main/sys"
import "core:mem"
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

_client: struct {
	media_controls_state:     player.State,
	playback_state:           player.State, // updated every frame
	font_allocator:           mem.Allocator,
	font_arena:               mem.Dynamic_Arena,
	frame_allocator:          mem.Allocator,
	frame_allocation_tracker: mem.Tracking_Allocator,
	system_fonts:             []sys.System_Font,
	window_title_track:       Maybe(lib.Track_ID),
	want_exit:                bool,

	paths: struct {
		data:   string,
		config: string,
		cache:  string,
	}
}

@(private="file")
run :: proc() -> shared.Error {
	tracking_allocator: mem.Tracking_Allocator

	client := &_client

	when ODIN_DEBUG {
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)
		defer {
			for ptr, alloc in tracking_allocator.allocation_map {
				fmt.println(alloc)
			}

			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

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

	media_controls.set_handler(media_controls_handler, nil)

	if !launch_config.headless {
		when ODIN_OS == .Windows do platform_init_win32() or_return
		else do platform_init_glfw() or_return
	}

	platform_make_window() or_return
	defer platform_destroy_window()

	// --------------------------------------------------------------------------
	// Get paths
	// --------------------------------------------------------------------------
	when ODIN_DEBUG {
		client.paths.config = "."
		client.paths.data   = "."
		client.paths.cache  = "." + filepath.SEPARATOR_STRING + "cache"

		shared.ensure_dir(client.paths.cache)
	}
	else {
		client.paths.config = os.user_config_dir(context.allocator) or_return
		client.paths.data =   os.user_data_dir(context.allocator) or_return
		client.paths.cache =  os.user_cache_dir(context.allocator) or_return
	}

	// --------------------------------------------------------------------------
	// Initialize client stuff
	// --------------------------------------------------------------------------
	{
		if launch_config.memory_debug {
			client.frame_allocator = shared.track_allocator(
				context.temp_allocator, &client.frame_allocation_tracker
			)
		}
		else {
			client.frame_allocator = context.temp_allocator
		}

		mem.dynamic_arena_init(&client.font_arena)
		client.font_allocator = mem.dynamic_arena_allocator(&client.font_arena)

		refresh_fonts() or_return
	}
	defer free_fonts()
	defer mem.dynamic_arena_destroy(&client.font_arena)

	ui_init() or_return
	defer ui_shutdown()

	for !_client.want_exit {
		free_all(client.frame_allocator)

		platform_poll_events()

		client.playback_state = player.get_state()

		// -----------------------------------------------------------------------
		// Update media controls
		// -----------------------------------------------------------------------
		if client.playback_state.track != client.media_controls_state.track {
			log.debug("Update media controls track")
			track_id := client.playback_state.track
			if track_id != nil {
				if track, ok := lib.get_track(track_id.?); ok {
					media_controls.update_track(track)
				}
			}
		}

		if client.playback_state != client.media_controls_state {
			log.debug("Update media controls state")
			media_controls.update_state(client.playback_state)
			client.media_controls_state = client.playback_state
		}

		// -----------------------------------------------------------------------
		// Update window title
		// -----------------------------------------------------------------------
		if client.playback_state.track != client.window_title_track {
			client.window_title_track = client.playback_state.track
			log.debug("Updating window title")

			if client.playback_state.track == nil {
				platform_set_window_title(shared.PROGRAM_NAME_AND_VERSION)
			}
			else if track, ok := lib.get_track(client.playback_state.track.?); ok {
				sb: strings.Builder
				defer strings.builder_destroy(&sb)

				sep :: " |"

				strings.write_string(&sb, shared.PROGRAM_NAME_AND_VERSION)
				if track.artists != nil {
					artists := lib.join_shared_strings(.Artist, track.artists, get_frame_allocator())
					fmt.sbprint(&sb, sep, artists, "-", track.title)
				}
				else {
					fmt.sbprint(&sb, sep, track.title)
				}

				if track.album != nil {
					fmt.sbprint(&sb, sep, lib.get_shared_string(.Album, track.album.?))
				}

				platform_set_window_title(strings.to_string(sb))
			}
		}

		// -----------------------------------------------------------------------
		// Show UI
		// -----------------------------------------------------------------------
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

media_controls_handler :: proc(_: rawptr, cmd: media_controls.Command) {
	player.lock()
	defer player.unlock()

	switch cmd {
	case .Pause: player.set_paused(true)
	case .Play: player.set_paused(false)
	case .Stop: player.stop_playback()
	case .ShuffleOn: player.set_shuffle_on(true)
	case .ShuffleOff: player.set_shuffle_on(false)
	case .Next: player.play_next_track()
	case .Prev: player.play_prev_track()
	case .RepeatTrack:
	case .RepeatPlaylist:
	case .RepeatOff:
	}
}

free_fonts :: proc() {
	client := &_client
	for font in client.system_fonts do sys.font_free(font)
	free_all(client.font_allocator)
	client.system_fonts = nil
}

refresh_fonts :: proc() -> shared.Error {
	client := &_client
	free_fonts()
	client.system_fonts = sys.font_list_system_fonts(client.font_allocator) or_return

	return nil
}

get_frame_allocator :: proc() -> mem.Allocator {
	return _client.frame_allocator
}

get_last_playback_state :: proc() -> player.State {
	return _client.playback_state
}

get_data_path :: proc() -> string {
	return _client.paths.data
}

get_config_path :: proc() -> string {
	return _client.paths.config
}

get_cache_path :: proc() -> string {
	return _client.paths.cache
}

request_exit :: proc() {
	_client.want_exit = true
}
