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
package server

import "core:sync"
Current_Track_Changed_Event :: struct {
	track_id: Track_ID,
}

State_Changed_Event :: struct {
	paused: bool,
}

Event :: union {
	Current_Track_Changed_Event,
	State_Changed_Event,
}

Event_Handler_Proc :: #type proc(state: Server, data: rawptr, event: Event)

Event_Handler :: struct {
	handler_proc: Event_Handler_Proc,
	data: rawptr,
}

add_event_handler :: proc(state: ^Server, handler: Event_Handler_Proc, data: rawptr) {
	append(&state.event_handlers, Event_Handler{
		handler_proc = handler,
		data = data,
	})
}

send_event :: proc(state: ^Server, event: Event) {
	sync.lock(&state.event_queue_lock)
	defer sync.unlock(&state.event_queue_lock)
	if state.wake_proc != nil {state.wake_proc()}
	append(&state.event_queue, event)
}

handle_events :: proc(state: ^Server) {
	sync.lock(&state.event_queue_lock)
	defer sync.unlock(&state.event_queue_lock)

	for handler in state.event_handlers {
		for event in state.event_queue {
			handler.handler_proc(state^, handler.data, event)
		}
	}
	clear(&state.event_queue)
	free_all(context.temp_allocator)

	flush_scan_queue(state)
	library_save_dirty_playlists(&state.library)
	_background_scan_output_results(&state.library, &state.background_scan)

	if state.library.serial != state.library_save_serial {
		state.library_save_serial = state.library.serial
		library_save_to_file(state.library, state.paths.library)
	}

	if state.library.folder_tree_serial != state.library.serial {
		state.library.folder_tree_serial = state.library.serial
		library_build_folder_tree(&state.library)
	}

	for &playlist in state.library.playlists {
		if playlist.auto_build_params == nil {continue}

		if playlist.auto_build_params.?.build_serial != state.library.serial {
			//playlist_list_build_auto_playlist(&state.library.user_playlists, state.library, index)
			playlist_build_from_auto_params(&playlist, &state.library)
			state.library.playlists_serial += 1
		}
	}
}
