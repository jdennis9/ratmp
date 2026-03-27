package main

Media_Controls_Event :: enum {
	Play,
	Pause,
	Toggle,
	Stop,
	Next,
	Prev,
	EnableShuffle,
	DisableShuffle,
}

Media_Controls_State :: struct {
	paused: bool,
	shuffle_enabled: bool,
	have_track: bool,
}

Media_Controls_Proc :: #type proc(data: rawptr, event: Media_Controls_Event)

_media_controls_impl_init: proc(cb: Media_Controls_Proc, cbd: rawptr) -> bool
_media_controls_impl_update_track: proc(sv: ^Server, track: Track)
_media_controls_impl_update_state: proc(state: Media_Controls_State)
_media_controls_impl_destroy: proc()

media_controls_init :: proc(cb: Media_Controls_Proc, cbd: rawptr) -> bool {
	if _media_controls_impl_init != nil {
		return _media_controls_impl_init(cb, cbd)
	}
	return true
}

media_controls_update_track :: proc(sv: ^Server, track: Track) {
	if _media_controls_impl_update_track != nil {
		_media_controls_impl_update_track(sv, track)
	}
}

media_controls_update_state :: proc(state: Media_Controls_State) {
	if _media_controls_impl_update_state != nil {
		_media_controls_impl_update_state(state)
	}
}

media_controls_destroy :: proc() {
	if _media_controls_impl_destroy != nil {
		_media_controls_impl_destroy()
	}
}
