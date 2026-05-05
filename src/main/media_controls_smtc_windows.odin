package main

import "core:strings"
import "base:runtime"
import smtc "src:bindings/media_controls_smtc"

_smtc: struct {
	ctx: runtime.Context,
	callback: Media_Controls_Proc,
	callback_data: rawptr,
}

media_controls_use_smtc :: proc() {
	_handler :: proc "c" (data: rawptr, signal: smtc.Signal) {
		context = _smtc.ctx

		signal_map := [smtc.Signal]Media_Controls_Event {
			.Play = .Play,
			.Pause = .Pause,
			.Next = .Next,
			.Prev = .Prev,
			.Stop = .Stop,
			.EnableShuffle = .EnableShuffle,
			.DisableShuffle = .DisableShuffle,
		}

		_smtc.callback(_smtc.callback_data, signal_map[signal])
	}

	_media_controls_impl_init = proc(cb: Media_Controls_Proc, cbd: rawptr) -> bool {
		_smtc.ctx = context
		_smtc.callback = cb
		_smtc.callback_data = cbd
		smtc.create(_handler, cbd)
		return true
	}

	_media_controls_impl_update_track = proc(sv: ^Server, track: Track) {
		cover_data, mime_type, have_cover_data := find_track_thumbnail(
			sv.library, track.id, context.allocator
		)
		defer if have_cover_data {
			delete(cover_data)
			delete(mime_type)
		}

		ti := smtc.Track_Info {
			album = track.album   != 0 ? strings.clone_to_cstring(get_album_name(sv^, track.album)) : nil,
			//artist = track.artist != 0 ? strings.clone_to_cstring(get_artist_name(sv^, track.artist)) : nil,
			//genre = track.genre   != 0 ? strings.clone_to_cstring(get_genre_name(sv^, track.genre)) : nil,
			title = track.title   != "" ? strings.clone_to_cstring(track.title) : nil,
			cover_data = raw_data(cover_data),
			cover_data_size = auto_cast len(cover_data),
		}

		defer {
			delete(ti.artist)
			delete(ti.album)
			delete(ti.title)
			delete(ti.genre)
		}

		smtc.set_track_info(ti)
	}

	_media_controls_impl_update_state = proc(state: Media_Controls_State) {
		s := smtc.State {
			have_track = state.have_track,
			paused = state.paused,
			shuffle = state.shuffle_enabled,
		}

		smtc.set_state(s)
	}

	_media_controls_impl_destroy = proc() {
		smtc.destroy()
	}
}
