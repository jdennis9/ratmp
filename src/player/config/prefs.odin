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
package config

import "base:runtime"
import "core:encoding/json"
import "core:path/filepath"
import "core:os"
import "core:strings"
import "core:fmt"
import "core:bytes"
import "core:log"
import "core:mem"

import "player:util"

Close_Policy :: enum {
	AlwaysAsk,
	MinimizeToTray,
	Exit,
}

Preferences :: struct {
	background_path: string,
	theme_name: string,
	font_path: string,
	font_size: int,
	icon_size: int,
	close_policy: Close_Policy,
	enable_media_controls: bool,
}

Preference_Manager :: struct {
	arena_data: []byte,
	arena: mem.Arena,
	values: Preferences,
	dirty: bool,
}

init_preferences :: proc() -> (prefs: Preference_Manager) {
	prefs.arena_data = make([]byte, 4096)
	mem.arena_init(&prefs.arena, prefs.arena_data)

	prefs.values = Preferences {
		font_size = 13,
		icon_size = 11,
		close_policy = .AlwaysAsk,
		enable_media_controls = true,
	}

	return
}

load_preferences :: proc(prefs: ^Preference_Manager, path: string) -> (loaded: bool) {
	log.debug("Loading preferences from", path)

	data := os.read_entire_file_from_filename(path) or_return
	mem.arena_free_all(&prefs.arena)
	unmarshal_error := json.unmarshal(data, &prefs.values, allocator = mem.arena_allocator(&prefs.arena))

	if unmarshal_error != nil {
		log.error("Error when loading preferences:", unmarshal_error)
		return
	}

	prefs.dirty = true
	loaded = true
	return
}

save_preferences :: proc(prefs: Preference_Manager, path: string) {
	log.debug("Saving preferences to", path)

	opt := json.Marshal_Options {
		use_enum_names = true,
		pretty = true,
	}

	data, marshal_error := json.marshal(prefs.values, opt)
	if marshal_error != nil {
		log.error("Error when saving preferences:", marshal_error)
		return
	}

	defer delete(data)

	file, file_error := util.overwrite_file(path)
	if file_error != nil {
		log.error("Error when saving preferences:", file_error)
		return
	}
	defer os.close(file)

	os.write(file, data)
}

copy_preferences :: proc(dst: ^Preference_Manager, src: Preferences) -> mem.Allocator_Error {
	if dst.arena_data == nil {
		dst^ = init_preferences()
	}

	mem.arena_free_all(&dst.arena)

	allocator := mem.arena_allocator(&dst.arena)

	dst.values.font_size = src.font_size
	dst.values.icon_size = src.icon_size
	dst.values.close_policy = src.close_policy
	dst.values.enable_media_controls = src.enable_media_controls
	dst.values.background_path = strings.clone(src.background_path, allocator) or_return
	dst.values.font_path = strings.clone(src.font_path, allocator) or_return
	dst.values.theme_name = strings.clone(src.theme_name, allocator) or_return
	dst.dirty = true

	return nil
}

free_preferences :: proc(prefs: Preference_Manager) {
	delete(prefs.arena_data)
}
