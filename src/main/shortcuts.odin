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

get_track :: proc(id: Track_ID) -> (track: Track, found: bool) {
	return library_get_track(id)
}

get_artist_name :: proc(id: Artist_ID) -> string {
	return library_get_artist_name(id)
}

get_album_name :: proc(id: Album_ID) -> string {
	return library_get_album_name(id)
}

get_genre_name :: proc(id: Genre_ID) -> string {
	return library_get_genre_name(id)
}
