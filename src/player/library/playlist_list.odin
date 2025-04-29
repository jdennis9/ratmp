/*
	RAT MP: A lightweight graphical music player
    Copyright (C) 2025 Jamie Dennis

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
package library

import "core:sort"
import "core:strings"
import "core:log"

filter_playlist :: proc(playlist: Playlist, filter_string: string) -> bool {
	filter_rune_buf: [128]rune
	filter_runes := _decode_utf8_to_buffer(filter_string, filter_rune_buf[:])

	return _filter_track_string(string(playlist.name), filter_runes)
}

update_playlist_list_filter :: proc(list: ^Playlist_List, filter: string, filter_hash: u32) {
	if list.filter_hash != filter_hash {
		list.filter_hash = filter_hash
		clear(&list.filter_indices)
		list.min_filter_index = max(i32)
		list.max_filter_index = 0

		for playlist, playlist_index in list.playlists {
			if filter_playlist(playlist, filter) {
				append(&list.filter_indices, auto_cast playlist_index)
				list.min_filter_index = min(list.min_filter_index, cast(i32) playlist_index)
				list.max_filter_index = max(list.max_filter_index, cast(i32) playlist_index)
			}
		}
	}
}

sort_playlist_list :: proc(list: ^Playlist_List) {
	if list.sort_metric == .None {return}

	compare_name_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		list := cast(^Playlist_List)iface.collection
		a := list.playlists[i]
		b := list.playlists[j]
		return strings.compare(string(a.name), string(b.name)) < 0
	}

	compare_length_proc :: proc(iface: sort.Interface, i, j: int) -> bool {
		list := cast(^Playlist_List)iface.collection
		a := list.playlists[i]
		b := list.playlists[j]
		return len(a.tracks) < len(b.tracks)
	}

	swap_proc :: proc(iface: sort.Interface, i, j: int) {
		list := cast(^Playlist_List)iface.collection
		temp := list.playlists[i]
		list.playlists[i] = list.playlists[j]
		list.playlists[j] = temp
	}

	len_proc :: proc(iface: sort.Interface) -> int {
		list := cast(^Playlist_List)iface.collection
		return len(list.playlists)
	}

	iface := sort.Interface {
		collection = list,
		len = len_proc,
		swap = swap_proc,
	}
	switch list.sort_metric {
		case .None:
		case .Length: {iface.less = compare_length_proc}
		case .Name: {iface.less = compare_name_proc}
	}

	if list.sort_order == .Ascending {sort.sort(iface)}
	else {sort.reverse_sort(iface)}
}

make_playlist_list_dirty :: proc(list: ^Playlist_List) {
	list.filter_hash = 0
}
