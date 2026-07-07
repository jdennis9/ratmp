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
package media_controls

import "core:strings"
import "core:mem"
import "base:runtime"
import "src:main/library"
import "src:main/player"
import "src:main/shared"
import smtc "src:bindings/media_controls_smtc"

_smtc: struct {
	ctx: runtime.Context
}

init_smtc :: proc() -> shared.Error {
	iface: Interface

	_smtc.ctx = context
	
	
	_handler :: proc "c" (data: rawptr, signal: smtc.Signal) {
		context = _smtc.ctx
		
		signal_map := [smtc.Signal]Command {
			.Play           = .Play,
			.Pause          = .Pause,
			.Next           = .Next,
			.Prev           = .Prev,
			.Stop           = .Stop,
			.EnableShuffle  = .ShuffleOn,
			.DisableShuffle = .ShuffleOff,
		}
		
		handle_command(signal_map[signal])
	}

	smtc.create(_handler, nil)
	
	iface.shutdown = proc() {
		smtc.destroy()
	}
	
	iface.update_state = proc(state: player.State) {
		s := smtc.State {
			have_track = !state.stopped,
			paused     = state.paused,
			shuffle    = state.shuffle_on,
		}
		
		smtc.set_state(s)
	}
	
	iface.update_track = proc(track: library.Track) {
		s: mem.Scratch
		mem.scratch_init(&s, 1<<10)
		defer mem.scratch_destroy(&s)
		
		context.temp_allocator = mem.scratch_allocator(&s)
		
		to_cstring :: proc(s: string) -> cstring {
			if s == "" do return nil
			return strings.clone_to_cstring(s, context.temp_allocator)
		}
		
		artists := library.join_shared_strings(.Artist, track.artists, context.temp_allocator)
		genres := library.join_shared_strings(.Genre, track.genres, context.temp_allocator)
		
		cover_art, have_cover_art := library.find_track_cover_art(track.handle, context.allocator)
		defer delete(cover_art)
		
		ti := smtc.Track_Info {
			album  = to_cstring(library.get_shared_string(.Album, track.album)),
			artist = to_cstring(artists),
			genre  = to_cstring(genres),
			title  = to_cstring(track.title),
		}
		
		if have_cover_art {
			ti.cover_data      = raw_data(cover_art)
			ti.cover_data_size = auto_cast len(cover_art)
		}

		smtc.set_track_info(ti)
	}

	set_impl(iface)

	return nil
}
