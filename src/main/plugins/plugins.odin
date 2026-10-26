package plugins

import "core:log"
import "core:os"
import "src:main/shared"
import "core:dynlib"
import "src:sdk"

Plugin_Load_Proc :: #type proc(s: ^sdk.SDK) -> sdk.Plugin_Info

Plugin :: struct {
	info:    sdk.Plugin_Info,
	show_ui: proc(),
}

@(private="file")
_plugins: struct {
	impl:   ^sdk.SDK,
	plugins: [dynamic; 500]Plugin,
}

init :: proc(impl: ^sdk.SDK) {
	_plugins.impl = impl
}

add_plugins_from_folder :: proc(path: string) -> shared.Error {
	files := os.read_all_directory_by_path(path, context.allocator) or_return
	defer os.file_info_slice_delete(files, context.allocator)

	for file in files {
		add_plugin_from_shared_lib(file.fullpath)
	}

	return nil
}

add_plugin_from_shared_lib :: proc(path: string) -> shared.Error {
	state := &_plugins
	p := dynlib.load_library(path) or_return

	load_proc := cast(Plugin_Load_Proc) dynlib.symbol_address(p, "RATMP_load_plugin")
	if load_proc == nil do return false

	info := load_proc(state.impl)

	append(&state.plugins, Plugin {
		info    = info,
		show_ui = cast(proc()) dynlib.symbol_address(p, "RATMP_show_ui"),
	})

	log.info("Loaded plugin:", info.display_name)

	return nil
}

on_show_ui :: proc() {
	state := &_plugins

	for p in state.plugins {
		if p.show_ui != nil do p.show_ui()
	}
}
