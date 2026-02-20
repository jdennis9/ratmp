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
package server

import "core:container/small_array"
import "core:reflect"
import "core:os"
import "core:os/os2"
import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:log"
import "core:encoding/ini"

Playlist_File_Error :: enum {
	None,
	Syntax,
	MissingFiles,
	InvalidPlaylist,
}

Playlist_File_Format :: enum {
	M3u,
	Rap,
}

Playlist_File_Format_Interface :: struct {
	extensions: []string,
	save: proc(lib: Library, input: Playlist, output: os.Handle) -> Playlist_File_Error,
	// Output playlist is already initialized, but the name and content need to filled in by this procedure
	parse: proc(lib: ^Library, input: string, output: ^Playlist) -> Playlist_File_Error,
}

DEFAULT_PLAYLIST_FORMAT :: Playlist_File_Format.M3u
DEFAULT_PLAYLIST_FORMAT_EXTENSION :: ".m3u"

PLAYLIST_FILE_FORMATS := [Playlist_File_Format]Playlist_File_Format_Interface {
	.M3u = {
		extensions = {".m3u"},
		parse = playlist_file_parse_m3u,
		save = playlist_file_save_m3u,
	},
	.Rap = {
		extensions = {".rap"},
		parse = playlist_file_parse_rap,
		save = playlist_file_save_rap,
	},
}


playlist_file_format_from_extension :: proc(extension: string) -> (Playlist_File_Format, bool) {
	for format, format_id in PLAYLIST_FILE_FORMATS {
		for ext in format.extensions {
			if extension == ext {
				return format_id, true
			}
		}
	}

	log.warn("Unknown playlist format extension", extension)
	return .M3u, false
}

// Format is decided by extension
playlist_file_save :: proc(lib: Library, input: Playlist, path: string) -> bool {
	format := playlist_file_format_from_extension(filepath.ext(path)) or_return

	if os2.exists(path) {os2.remove(path)}
	file, file_error := os2.create(path)
	if file_error != nil {return false}
	defer os2.close(file)

	error := PLAYLIST_FILE_FORMATS[format].save(lib, input, auto_cast os2.fd(file))

	if error != .None {
		log.error("Error when saving playlist", input.name, ":", error)
	}

	return error == .None
}

// Format is decided by extension
playlist_file_load :: proc(lib: ^Library, path: string, output: ^Playlist) -> (ok: bool) {
	format := playlist_file_format_from_extension(filepath.ext(path)) or_return
	data, _ := os2.read_entire_file_from_path(path, context.allocator)
	if data == nil {return false}
	defer delete(data)

	error := PLAYLIST_FILE_FORMATS[format].parse(lib, string(data), output)

	return error == .None
}

playlist_file_save_m3u :: proc(lib: Library, input: Playlist, output: os.Handle) -> Playlist_File_Error {
	fp :: fmt.fprintln

	fp(output, "#EXTM3U")
	fp(output, "#PLAYLIST:", input.name, sep="")

	for track_id in input.tracks {
		path_buf: [512]u8
		path := library_find_track_path(lib, path_buf[:], track_id) or_continue
		fp(output, path)
	}

	return .None
}

playlist_file_parse_m3u :: proc(
	lib: ^Library, input: string, output: ^Playlist
) -> (error: Playlist_File_Error) {
	lines := strings.split_lines(input)
	defer delete(lines)
	if len(lines) == 0 {return .Syntax}
	if strings.trim(lines[0], " ") != "#EXTM3U" {return .Syntax}

	track_paths: [dynamic]string
	defer delete(track_paths)

	for line in lines[1:] {
		if line == "" {continue}

		if strings.starts_with(line, "#PLAYLIST:") {
			parts := strings.split_n(line, ":", 2)
			defer delete(parts)

			if len(parts) != 2 {
				log.error("m3u parse error: Expected playlist name after #PLAYLIST:")
				return .Syntax
			}

			library_set_playlist_name(lib, output, strings.trim(parts[1], " "))
		}
		else if strings.starts_with(line, "#") {
			continue
		}
		else {
			append(&track_paths, strings.trim(line, " "))
		}
	}

	if output.name == "" {
		return .Syntax
	}

	for track_path in track_paths {
		path_hash := library_hash_path(track_path)
		track_index := library_find_track_by_path_hash(lib^, path_hash) or_continue
		track := lib.tracks[track_index]
		playlist_add_tracks(output, lib, {track.id}, assume_unique=true)
	}

	return .None
}

playlist_file_parse_rap :: proc(
	lib: ^Library, input: string, output: ^Playlist
) -> (error: Playlist_File_Error) {
	data, parse_error := ini.load_map_from_string(input, context.allocator)
	defer ini.delete_map(data)
	if parse_error != nil {return .Syntax}
	params: Playlist_Auto_Build_Params

	meta_section, have_meta_section := data["Meta"]
	if !have_meta_section {return .Syntax}

	name, have_name := meta_section["Name"]
	if !have_name {return .Syntax}

	defer output.auto_build_params = params
	library_set_playlist_name(lib, output, name)

	for section_name, section in data {
		param: Playlist_Auto_Build_Param
		if section_name == "Meta" {continue}
		type := reflect.enum_from_name(Playlist_Auto_Build_Param_Type, section["Type"]) or_continue
		filter := section["Filter"] or_continue

		param.type = type
		copy(param.arg[:len(param.arg)-1], filter)

		small_array.append(&params.params, param)
	}

	return .None
}

playlist_file_save_rap :: proc(lib: Library, input: Playlist, output: os.Handle) -> Playlist_File_Error {
	fp :: fmt.fprintln
	fpf :: fmt.fprintfln

	if input.auto_build_params == nil {return .InvalidPlaylist}
	params := input.auto_build_params.?

	fp(output, "[Meta]")
	fpf(output, "Name=%s", string(input.name))
	fp(output)

	for &param, index in small_array.slice(&params.params) {
		fpf(output, "[Param%d]", index)
		fpf(output, "Type=%s", reflect.enum_string(param.type))
		fpf(output, "Filter=%s", string(cstring(&param.arg[0])))
		fp(output)
	}

	return .None
}
