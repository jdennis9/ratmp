#+private
package client

import imgui "src:thirdparty/odin-imgui"

import "src:server"

_Track_Filter_State :: struct {
	filter: [512]u8,
	spec: server.Track_Filter_Spec,
	output: [dynamic]Track_ID,
	serial: uint,
	playlist_id: Playlist_ID,
}

_track_filter_update :: proc(
	state: ^_Track_Filter_State,
	lib: server.Library, input: []Track_ID,
	playlist_id: Playlist_ID, serial: uint
) -> []Track_ID {
	apply_filter: bool
	filter_cstring := cstring(&state.filter[0])

	if state.spec.components == {} {
		state.spec.components = ~{}
	}

	apply_filter |= imgui.InputTextWithHint("##filter", "Filter", filter_cstring, len(state.filter))
	apply_filter |= state.serial != serial
	apply_filter |= state.playlist_id != playlist_id

	if state.filter[0] == 0 {
		return input
	}
	else if apply_filter {
		clear(&state.output)
		state.serial = serial
		state.playlist_id = playlist_id
		state.spec.filter = string(filter_cstring)
		server.filter_tracks(lib, state.spec, input, &state.output)
		return state.output[:]
	}
	else if state.filter[0] != 0 {
		return state.output[:]
	}

	return input
}

_track_filter_destroy :: proc(state: ^_Track_Filter_State) {
	delete(state.output)
	state.output = nil
}
