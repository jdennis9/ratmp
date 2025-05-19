#+private
package client

import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

_Layout_State :: struct {
	layout_to_load: []u8,
	free_layout_after_load: bool,
	layout_names: [dynamic]cstring,
	save_layout_name: [64]u8,
	save_layout_error: cstring,
}

_load_layout_from_memory :: proc(client: ^Client, data: []u8, free_after_load: bool) {
	state := &client.layouts

	state.layout_to_load = data
	state.free_layout_after_load = free_after_load
}

_get_layout_path_from_name :: proc(client: Client, name: string, allocator := context.allocator) -> string {
	filename := fmt.aprint(name, ".ini", sep="")
	defer delete(filename)
	return filepath.join({client.paths.layout_folder, filename}, allocator)
}

_load_layout_from_name :: proc(client: ^Client, name: string) {
	state := &client.layouts

	path := _get_layout_path_from_name(client^, name)

	data, read_error := os2.read_entire_file_from_path(path, context.allocator)
	if read_error != nil {return}

	state.layout_to_load = data
	state.free_layout_after_load = true
}

_scan_layouts_folder :: proc(client: ^Client) {
	state := &client.layouts

	if !os2.exists(client.paths.layout_folder) {
		os2.make_directory_all(client.paths.layout_folder)
	}

	// Free name list
	for name in state.layout_names {delete(name)}
	delete(state.layout_names)
	client.layouts.layout_names = nil

	files, dir_error := os2.read_all_directory_by_path(client.paths.layout_folder, context.allocator)
	if dir_error != nil {return}
	defer os2.file_info_slice_delete(files, context.allocator)

	for file in files {
		name := filepath.stem(filepath.base(file.fullpath))
		append(&state.layout_names, strings.clone_to_cstring(name))
	}
}

_layouts_destroy :: proc(client: ^Client) {
	state := &client.layouts
	for name in state.layout_names {
		delete(name)
	}
	delete(state.layout_names)
	if state.free_layout_after_load && state.layout_to_load != nil {
		delete(state.layout_to_load)
	}
}

_update_layout :: proc(client: ^Client) {
	state := &client.layouts

	if state.layout_to_load != nil {
		for &window in client.window_state {
			window.show = false
			window.bring_to_front = false
		}

		imgui.LoadIniSettingsFromMemory(cstring(raw_data(state.layout_to_load)), auto_cast len(state.layout_to_load))

		if state.free_layout_after_load {
			state.free_layout_after_load = false
			delete(state.layout_to_load)
		}

		state.layout_to_load = nil
	}
}

_layout_exists :: proc(client: ^Client, name: string) -> bool {
	for layout in client.layouts.layout_names {
		if string(layout) == name {return true}
	}
	return false
}

_save_layout :: proc(client: ^Client, name: string) {
	path := _get_layout_path_from_name(client^, name)
	defer delete(path)
	path_cstring := strings.clone_to_cstring(path)
	defer delete(path_cstring)

	imgui.SaveIniSettingsToDisk(path_cstring)

	_scan_layouts_folder(client)
}

_show_layout_menu_items :: proc(client: ^Client, save_layout_popup_id: imgui.ID) {
	state := &client.layouts
	if imgui.MenuItem("Reset layout") {
		_load_layout_from_memory(client, DEFAULT_LAYOUT_INI, false)
	}
	imgui.SeparatorText("Load layout")
	for layout_name in state.layout_names {
		if imgui.MenuItem(layout_name) {
			_load_layout_from_name(client, string(layout_name))
		}
	}
	imgui.Separator()
	if imgui.MenuItem("Save current layout") {
		imgui.OpenPopupEx(save_layout_popup_id)
	}
	if imgui.MenuItem("Refresh layouts") {
		_scan_layouts_folder(client)
	}
}

_show_save_layout_popup :: proc(client: ^Client, id: imgui.ID) {
	state := &client.layouts
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
		else if !_layout_exists(client, string(name)) {
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
			_save_layout(client, string(name))
			imgui.CloseCurrentPopup()
		}

		imgui.EndPopup()
	}


}

DEFAULT_LAYOUT_INI :: #load("default_layout.ini")
