package library

import "core:testing"

import "player:util"

@test
test_adding_tracks :: proc(t: ^testing.T) {
	lib: Library
	metadata: Raw_Track_Info

	util.copy_string_to_buf(metadata.artist[:], "Some")
	util.copy_string_to_buf(metadata.title[:], "Music")
	util.copy_string_to_buf(metadata.genre[:], "A genre")
	util.copy_string_to_buf(metadata.album[:], "Album")

	_add_track(&lib, "folder/some_file.mp3", metadata)

	testing.expect(t, len(lib.folders.playlists) == 1)
	testing.expect(t, len(lib.genres.playlists) == 1)
	testing.expect(t, len(lib.artists.playlists) == 1)
	testing.expect(t, len(lib.albums.playlists) == 1)

	destroy(lib)
}

@test
test_adding_playlists :: proc(t: ^testing.T) {
	lib := init("")

	_, error := add_playlist(&lib, "A playlist")
	testing.expect(t, error == .None)

	_, error = add_playlist(&lib, "")
	testing.expect(t, error == .EmptyName)

	_, error = add_playlist(&lib, "A playlist")
	testing.expect(t, error == .NameExists)

	destroy(lib)
}
