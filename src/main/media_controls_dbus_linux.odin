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
package main

import "core:log"
import "core:path/filepath"
import "core:os"
import "core:strings"
import "base:runtime"
import impl "src:bindings/media_controls_dbus"

@(private="file")
_dbus: struct {
	callback: Media_Controls_Proc,
	callback_data: rawptr,
	ctx: runtime.Context,
}

media_controls_use_dbus :: proc() {
	_write_thumbnail_to_file :: proc(sv: ^Server, track_id: Track_ID) -> (uri: cstring, ok: bool) {
		user_cache_dir, dir_error := os.user_cache_dir(context.allocator)
		defer delete(user_cache_dir)

		if dir_error != nil {
			log.error(dir_error)
			return
		}

		data, mime_type := find_track_thumbnail(sv.library, track_id, context.allocator) or_return
		defer delete(data)
		defer delete(mime_type)

		extension: string		
		switch mime_type {
			case "image/jpeg": extension = "jpg"
			case "image/png": extension = "png"
			case "image/webp": extension = "webp"
			case "image/tiff": extension = "tiff"
			case "image/bmp": extension = "bmp"
			case: return
		}

		cover_file_name := strings.join({user_cache_dir, "/ratmp/cover.", extension}, "", context.allocator)
		defer delete(cover_file_name)
		cover_uri := strings.join({"file://", cover_file_name}, "", context.allocator)
		defer delete(cover_uri)

		log.debug("Writing thumbnail to", cover_file_name)

		if !os.exists(filepath.dir(cover_file_name)) {
			os.make_directory(filepath.dir(cover_file_name))
		}

		file, file_error := os.create(cover_file_name)
		if file_error != nil {
			log.error(file_error)
			return
		}
		defer os.close(file)

		os.write(file, data)

		ok = true
		return strings.clone_to_cstring(cover_uri), true
	}

	_handler_wrapper :: proc "c" (_: rawptr, signal: impl.Signal) {
		context = _dbus.ctx

		if _dbus.callback == nil do return
		if signal > max(impl.Signal) || signal < min(impl.Signal) do return

		signal_to_event := [impl.Signal]Media_Controls_Event {
			.Play = .Play,
			.Pause = .Pause,
			.Stop = .Stop,
			.Next = .Next,
			.Prev = .Prev,
			.EnableShuffle = .EnableShuffle,
			.DisableShuffle = .DisableShuffle,
		}

		_dbus.callback(_dbus.callback_data, signal_to_event[signal])
	}

	_media_controls_impl_init = proc(cb: Media_Controls_Proc, cbd: rawptr) -> bool {
		_dbus.callback = cb
		_dbus.callback_data = cbd
		_dbus.ctx = context

		impl.enable(_handler_wrapper, nil)

		return true
	}

	_media_controls_impl_update_track = proc(sv: ^Server, track: Media_Controls_Track_Info) {

		ti := impl.Track_Info {
			album     = track.album   != "" ? strings.clone_to_cstring(track.album) : nil,
			artist    = track.artists != "" ? strings.clone_to_cstring(track.artists) : nil,
			genre     = track.genres  != "" ? strings.clone_to_cstring(track.genres) : nil,
			title     = track.title   != "" ? strings.clone_to_cstring(track.title) : nil,
			path      = strings.clone_to_cstring(track.url),
			cover_uri = _write_thumbnail_to_file(sv, track.id) or_else nil,
		}

		defer {
			delete(ti.album)
			delete(ti.artist)
			delete(ti.genre)
			delete(ti.title)
			delete(ti.path)
			delete(ti.cover_uri)
		}

		impl.set_track_info(&ti)
	}

	_media_controls_impl_update_state = proc(state: Media_Controls_State) {
		s := impl.State {
			have_track = state.have_track,
			paused = state.paused,
			shuffle = state.shuffle_enabled,
		}

		impl.set_state(s)
	}

	_media_controls_impl_destroy = proc() {
		impl.disable()
	}
}
