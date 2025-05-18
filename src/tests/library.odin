package tests

import "core:testing"

import "src:server"

@test
test_library_track_management :: proc(t: ^testing.T) {
	lib: server.Library
	
	server.library_init(&lib)
	defer server.library_destroy(&lib)

	track: server.Track_Metadata
	server.track_set_string(&track, .Artist, "Artist", lib.string_allocator)
	server.track_set_string(&track, .Title, "Title", lib.string_allocator)
	server.track_set_string(&track, .Album, "Album", lib.string_allocator)

	id := server.library_add_track(&lib, "path/track.mp3", track)
	testing.expect(t, server.library_add_track(&lib, "path/track.mp3", track) == id)
	id = server.library_add_track(&lib, "path/another_track.mp3", track)
	testing.expect(t, id == 2)
}

@test
test_library_sort :: proc(t: ^testing.T) {
	lib: server.Library
	A: server.Track_Metadata
	B: server.Track_Metadata
	C: server.Track_Metadata

	server.library_init(&lib)
	defer server.library_destroy(&lib)

	tracks := [3]server.Track_ID {2, 3, 1}

	server.track_set_string(&A, .Title, "A", lib.string_allocator)
	A.values[.Duration] = 1
	server.track_set_string(&B, .Title, "B", lib.string_allocator)
	B.values[.Duration] = 2
	server.track_set_string(&C, .Title, "C", lib.string_allocator)
	C.values[.Duration] = 3

	server.library_add_track(&lib, "A.mp3", A)
	server.library_add_track(&lib, "B.mp3", B)
	server.library_add_track(&lib, "C.mp3", C)

	server.sort_tracks(lib, tracks[:], {metric = .Title, order = .Descending})
	testing.expect(t, tracks == {1, 2, 3})
	server.sort_tracks(lib, tracks[:], {metric = .Title, order = .Ascending})
	testing.expect(t, tracks == {3, 2, 1})

	tracks = {2, 3, 1}
	server.sort_tracks(lib, tracks[:], {metric = .Duration, order = .Ascending})
	testing.expect(t, tracks == {1, 2, 3})
}

@test
test_library_scan :: proc(t: ^testing.T) {
	lib: server.Library
	set: server.Track_Set

	server.library_init(&lib)
	defer server.delete_track_set(&set)
	defer server.library_destroy(&lib)

	server.scan_directory_tracks("D:\\Media\\Music\\Anime", &set)
	server.library_add_track_set(&lib, set)

	testing.expect(t, len(lib.track_metadata) == len(set.metadata))
}
