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

import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:os"
import "core:io"
import hm "core:container/handle_map"
import "core:slice"

Playlist_Handle :: hm.Handle32

Playlist :: struct {
	handle:       Playlist_Handle,
	uid:          UID,
	name:         string,
	name_cstring: cstring,
	tracks:       [dynamic]Track_ID,
	serial:       uint,
	save_serial:  uint,
	file:         string,
}

Playlist_Format_Interface :: struct {
	extension: string,
	save: proc(l: Library, playlist: Playlist, stream: io.Stream) -> Error,
	load: proc(l: Library, data: []byte) -> (Playlist, Error),
}

Playlist_Format :: enum {M3u}

PLAYLIST_FORMATS := [Playlist_Format]Playlist_Format_Interface {
	.M3u = {
		extension = ".m3u",
		save = _m3u_save,
		load = _m3u_load,
	},
}

playlist_add :: proc(sv: ^Server, pl: ^Playlist, tracks: []Track_ID) {
	for track_id in tracks {
		if slice.contains(pl.tracks[:], track_id) do continue
		append(&pl.tracks, track_id)
	}

	pl.serial += 1
}

playlist_remove :: proc(sv: ^Server, pl: ^Playlist, tracks: []Track_ID) {
	for track_id in tracks {
		index := slice.linear_search(pl.tracks[:], track_id) or_continue
		ordered_remove(&pl.tracks, index)
	}

	pl.serial += 1
}

playlist_save :: proc(l: Library, pl: Playlist, path: string, format := Playlist_Format.M3u) -> Error {
	iface := PLAYLIST_FORMATS[format]
	f := os.create(path) or_return
	defer os.close(f)

	return iface.save(l, pl, os.to_stream(f))
}

playlist_save_to_dir :: proc(l: Library, pl: ^Playlist, dir: string) -> Error {
	if pl.file == "" {
		temp_file := os.create_temp_file(dir, "*.m3u") or_return
		pl.file = strings.clone(os.name(temp_file), l.allocators.track_data)
		os.close(temp_file)
	}

	playlist_save(l, pl^, pl.file) or_return
	return nil
}

playlist_load :: proc(l: Library, path: string) -> (pl: Playlist, error: Error) {
	format := playlist_format_from_extension(filepath.ext(path)) or_return
	data := os.read_entire_file_from_path(path, context.allocator) or_return
	defer delete(data)

	return PLAYLIST_FORMATS[format].load(l, data)
}

playlist_format_from_extension :: proc(ext: string) -> (Playlist_Format, bool) {
	for info, f in PLAYLIST_FORMATS {
		if info.extension == ext do return f, true
	}

	return nil, false
}

playlist_set_name :: proc(l: Library, pl: ^Playlist, name: string) {
	pl.name_cstring = strings.clone_to_cstring(name, l.allocators.track_data)
	pl.name = string(pl.name_cstring)
}

@(private="file")
_m3u_save :: proc(l: Library, pl: Playlist, s: io.Stream) -> Error {
	fmt.wprintln(s, "#EXTM3U")
	fmt.wprintln(s, "#PLAYLIST:", pl.name, sep="")
	
	for track_id in pl.tracks {
		track := library_get_track(l, track_id) or_continue
		fmt.wprintln(s, track.url)
	}

	return nil
}

@(private="file")
_m3u_load :: proc(l: Library, data: []byte) -> (pl: Playlist, error: Error) {
	lines := strings.split_lines(string(data))
	defer delete(lines)

	error = Custom_Error.InvalidInput

	if len(lines) == 0 do return
	if strings.trim_space(lines[0]) != "#EXTM3U" do return

	for line in lines[1:] {
		if line == "" do continue

		if strings.starts_with(line, "#PLAYLIST:") {
			parts := strings.split_n(line, ":", 2)
			defer delete(parts)

			if len(parts) != 2 do return

			playlist_set_name(l, &pl, parts[1])
		}
		else if strings.starts_with(line, "#") do continue
		else {
			track_path := strings.trim_space(line)

			track_path, _ = filepath.clean(track_path)
			defer delete(track_path)

			path_hash := stable_hash_string_64(track_path)
			track := library_get_track_id_from_path_hash(l, path_hash) or_continue

			append(&pl.tracks, track)
		}
	}

	if pl.name == "" do return

	error = nil
	return
}
