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

import "player:util"

Playlist_Sort_Metric :: enum {
	None,
	Name,
	Length,
}

Playlist_Sort_Spec :: struct {
	metric: Playlist_Sort_Metric,
	order: Sort_Order,
}

filter_playlist_from_runes :: proc(playlist: Playlist, filter_runes: []rune) -> bool {
	return _filter_track_string(string(playlist.name), filter_runes)
}

filter_playlist :: proc(playlist: Playlist, filter_string: string) -> bool {
	filter_rune_buf: [128]rune
	filter_runes := util.decode_utf8_to_runes(filter_rune_buf[:], filter_string)

	return filter_playlist_from_runes(playlist, filter_runes)
}

sort_playlist_list :: proc(playlists_arg: Playlist_List, spec: Playlist_Sort_Spec) {
	playlists := playlists_arg
	if spec.metric == .None {return}

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
		collection = &playlists,
		len = len_proc,
		swap = swap_proc,
	}
	switch spec.metric {
		case .None:
		case .Length: {iface.less = compare_length_proc}
		case .Name: {iface.less = compare_name_proc}
	}

	if spec.order == .Ascending {sort.sort(iface)}
	else {sort.reverse_sort(iface)}
}

delete_playlist_list :: proc(list: Playlist_List) {
	delete(list.hashes)
	for playlist in list.playlists {
		free_playlist(playlist)
	}
	delete(list.playlists)
}
