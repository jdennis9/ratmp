package tests

/*import "core:testing"

import app ".."

@test
test_playback :: proc(t: ^testing.T) {
	playback: app.Playback
	ok: bool

	playback, ok = app.playback_init()
	testing.expect(t, ok)
	defer app.playback_destroy(playback)

	testing.expect(t, app.playback_play_file(&playback, "../src/tests/stereo.mp3"))

	for app.playback_is_playing(playback) {
	}
}*/
