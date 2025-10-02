/*
    RAT MP - A cross-platform, extensible music player
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
#+private
package client

import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

Layout_Manager :: struct {
	layout_to_load: []u8,
	free_layout_after_load: bool,
	layout_names: [dynamic]cstring,
	
	save_layout_name: [64]u8,
	save_layout_error: cstring,
	layouts_folder: string,

	want_save_layout: bool,
	want_save_layout_name: string,
}

load_layout_from_memory :: proc(state: ^Layout_Manager, data: []u8, free_after_load: bool) {
	state.layout_to_load = data
	state.free_layout_after_load = free_after_load
}

get_layout_path_from_name :: proc(state: ^Layout_Manager, name: string, allocator := context.allocator) -> string {
	filename := fmt.aprint(name, ".ini", sep="")
	defer delete(filename)
	return filepath.join({state.layouts_folder, filename}, allocator)
}

load_layout_from_name :: proc(state: ^Layout_Manager, name: string) {
	path := get_layout_path_from_name(state, name)
	data, read_error := os2.read_entire_file_from_path(path, context.allocator)
	if read_error != nil {return}

	state.layout_to_load = data
	state.free_layout_after_load = true
}

scan_layouts_folder :: proc(state: ^Layout_Manager) {
	if !os2.exists(state.layouts_folder) {
		os2.make_directory_all(state.layouts_folder)
	}

	// Free name list
	for name in state.layout_names {delete(name)}
	delete(state.layout_names)
	state.layout_names = nil

	files, dir_error := os2.read_all_directory_by_path(state.layouts_folder, context.allocator)
	if dir_error != nil {return}
	defer os2.file_info_slice_delete(files, context.allocator)

	for file in files {
		name := filepath.stem(filepath.base(file.fullpath))
		append(&state.layout_names, strings.clone_to_cstring(name))
	}
}

layouts_init :: proc(state: ^Layout_Manager, data_dir: string) {
	state.layouts_folder = filepath.join({data_dir, "Layouts"})
	scan_layouts_folder(state)
}

layouts_destroy :: proc(state: ^Layout_Manager) {
	for name in state.layout_names {
		delete(name)
	}
	delete(state.layout_names)
	if state.free_layout_after_load && state.layout_to_load != nil {
		delete(state.layout_to_load)
	}
	delete(state.layouts_folder)
}

update_layout :: proc(state: ^Layout_Manager, window_state: ^map[Window_ID]Saved_Window) {
	if state.layout_to_load != nil {
		for _, &window in window_state {
			window.open = false
			//window.bring_to_front = false
		}

		imgui.LoadIniSettingsFromMemory(cstring(raw_data(state.layout_to_load)), auto_cast len(state.layout_to_load))

		if state.free_layout_after_load {
			state.free_layout_after_load = false
			delete(state.layout_to_load)
		}

		state.layout_to_load = nil
	}

	if state.want_save_layout && state.want_save_layout_name != "" {
		state.want_save_layout = false

		path := get_layout_path_from_name(state, state.want_save_layout_name)
		defer delete(path)
		path_cstring := strings.clone_to_cstring(path)
		defer delete(path_cstring)

		imgui.SaveIniSettingsToDisk(path_cstring)

		scan_layouts_folder(state)
		delete(state.want_save_layout_name)
		state.want_save_layout_name = ""
	}
}

layout_exists :: proc(state: ^Layout_Manager, name: string) -> bool {
	for layout in state.layout_names {
		if string(layout) == name {return true}
	}
	return false
}

save_layout :: proc(state: ^Layout_Manager, name: string) {
	state.want_save_layout = true
	state.want_save_layout_name = strings.clone(name)
}

show_layout_menu_items :: proc(state: ^Layout_Manager, save_layout_popup_id: imgui.ID) {
	if imgui.MenuItem("Reset layout") {
		load_layout_from_memory(state, DEFAULT_LAYOUT_INI, false)
	}
	imgui.SeparatorText("Load layout")
	for layout_name in state.layout_names {
		if imgui.MenuItem(layout_name) {
			load_layout_from_name(state, string(layout_name))
		}
	}
	imgui.Separator()
	if imgui.MenuItem("Save current layout") {
		imgui.OpenPopupEx(save_layout_popup_id, 0)
	}
	if imgui.MenuItem("Refresh layouts") {
		scan_layouts_folder(state)
	}
}

show_save_layout_popup :: proc(state: ^Layout_Manager, id: imgui.ID) {
	save := false
	name := cstring(&state.save_layout_name[0])

	if imgui.BeginPopupEx(id, {}) {
		imgui.TextUnformatted("Name your layout")

		save |= imgui.InputText("##layout_name", name, len(state.save_layout_name), {.EnterReturnsTrue})

		if state.save_layout_name[0] == 0 {
			imgui.BeginDisabled()
			imgui.Button("Save")
			imgui.EndDisabled()
		}
		else if !layout_exists(state, string(name)) {
			save |= imgui.Button("Save")
		}
		else {
			save |= imgui.Button("Overwrite")
		}

		imgui.SameLine()
		
		if imgui.Button("Cancel") {
			imgui.CloseCurrentPopup()
		}

		if save {
			save_layout(state, string(name))
			imgui.CloseCurrentPopup()
		}

		imgui.EndPopup()
	}


}

DEFAULT_LAYOUT_INI :: #load("data/default_layout.ini")
