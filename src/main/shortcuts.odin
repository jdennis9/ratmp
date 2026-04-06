package main

get_track :: proc(sv: ^Server, id: Track_ID) -> (track: Track, found: bool) {
	return library_get_track(sv.library, id)
}

get_artist_name :: proc(sv: Server, id: Artist_ID) -> string {
	return library_get_artist_name(sv.library, id)
}

get_album_name :: proc(sv: Server, id: Album_ID) -> string {
	return library_get_album_name(sv.library, id)
}

get_genre_name :: proc(sv: Server, id: Genre_ID) -> string {
	return library_get_genre_name(sv.library, id)
}
