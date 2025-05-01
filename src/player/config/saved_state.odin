package config

import "base:runtime"
import "core:encoding/json"
import "core:strings"
import "core:log"
import "core:os/os2"

Saved_State :: struct {
	shuffle_enabled: bool,
	prefer_peak_meter_in_menu_bar: bool,
}

save_state :: proc(state: Saved_State, path: string) {
	opt: json.Marshal_Options

	data, marshal_error := json.marshal(state, opt)
	
	file, file_error := os2.create(path)	
	if file_error != nil {
		log.error(file_error)
		return
	}
	defer os2.close(file)
	os2.write(file, data)
}

load_state :: proc(path: string) -> (state: Saved_State, loaded: bool) {
	data, read_error := os2.read_entire_file_from_path(path, context.allocator)
	if read_error != nil {
		log.error(read_error)
		return
	}
	defer delete(data)

	unmarshal_error := json.unmarshal(data, &state)
	if unmarshal_error != nil {
		log.error(unmarshal_error)
		return
	}

	loaded = true
	return
}
