package main

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

	_media_controls_impl_update_track = proc(track: Track) {
		ti := impl.Track_Info {
			album = track.album != "" ? strings.clone_to_cstring(track.album) : nil,
			artist = track.artist != "" ? strings.clone_to_cstring(track.artist) : nil,
			genre = track.genre != "" ? strings.clone_to_cstring(track.genre) : nil,
			title = track.title != "" ? strings.clone_to_cstring(track.title) : nil,
			path = strings.clone_to_cstring(track.url),
		}

		defer {
			delete(ti.album)
			delete(ti.artist)
			delete(ti.genre)
			delete(ti.title)
			delete(ti.path)
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
