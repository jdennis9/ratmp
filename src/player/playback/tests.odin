package playback

import "core:testing"

import "player:audio"

@test
test_init_and_destroy :: proc(t: ^testing.T) {
	state, ok := init()
	testing.expect(t, ok)
	destroy(&state)
}

@test
test_audio_playback :: proc(t: ^testing.T) {
	Callback_State :: struct {
		state: ^State,
		stream: ^audio.Stream,
		eof: bool,
	}

	callback :: proc(data: rawptr, buffer: []f32) {
		cb := cast(^Callback_State) data
		cb.eof = stream(cb.state, buffer, cb.stream.samplerate, cb.stream.channels)
	}

	testing.expect(t, audio.init())
	defer audio.shutdown()

	state, ok := init()
	testing.expect(t, ok)
	defer destroy(&state)

	device_id, have_device := audio.get_default_device_id()
	testing.expect(t, have_device)

	callback_state := Callback_State {
		state = &state,
	}

	callback_state.stream, ok = audio.open_stream(&device_id, callback, &callback_state)
	testing.expect(t, ok)
	defer audio.close_stream(callback_state.stream)

	play :: proc(t: ^testing.T, state: ^State, callback_state: ^Callback_State, path: string) {
		testing.expect(t, _play_file(state, path))
		set_paused(state, false)
		testing.expect(t, state.paused == false)

		for !callback_state.eof {}
		callback_state.eof = false
	}
	
	play(t, &state, &callback_state, "../test_data/mono.mp3")
	play(t, &state, &callback_state, "../test_data/stereo.mp3")
}

