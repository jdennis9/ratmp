package main

import "core:slice"
import "core:os"
import "core:encoding/json"
import "core:mem"

CONFIG_MAX_FONTS :: 30

Config_Close_Policy :: enum {
	Ask,
	Exit,
	Minimize,
}

Config_Font :: struct {
	name_buf: [128]u8 `json:"-"`,
	name: cstring,
}

Config :: struct {
	server: struct {
		notify_new_track: bool,
		notify_library_scan: bool,
		notify_background_playback_state: bool,
	},
	ui: struct {
		background_buf: [512]u8 `json:"-"`,
		default_theme_buf: [128]u8 `json:"-"`,
		fonts_buf: [CONFIG_MAX_FONTS]Config_Font `json:"-"`,
		
		background: cstring,
		default_theme: cstring,
		font_size: f32,
		// @TODO: Used fixed length dynamic array when those
		// are added.
		// Slice of fonts_buf
		fonts: []Config_Font,
		close_policy: Config_Close_Policy,
	},
}

config_init_buffers :: proc(cfg: ^Config) {
	cfg.ui.default_theme = cstring(&cfg.ui.default_theme_buf[0])
	cfg.ui.background = cstring(&cfg.ui.background_buf[0])

	for &f in cfg.ui.fonts_buf {
		f.name = cstring(&f.name_buf[0])
	}

	cfg.ui.fonts = cfg.ui.fonts_buf[:len(cfg.ui.fonts)]
}

config_add_font :: proc(cfg: ^Config, name: string) {
	index := len(cfg.ui.fonts)
	if index >= CONFIG_MAX_FONTS do return

	cfg.ui.fonts = cfg.ui.fonts_buf[:index+1]
	set_cstring_buf(cfg.ui.fonts[index].name_buf[:], name)
}

config_remove_font :: proc(cfg: ^Config, index: int) {
	if index >= len(cfg.ui.fonts) do return
	if index + 1 != len(cfg.ui.fonts) {
		for i in index..<len(cfg.ui.fonts)-1 {
			cfg.ui.fonts[i].name_buf = cfg.ui.fonts[i+1].name_buf
		}
	}
	cfg.ui.fonts = cfg.ui.fonts_buf[:len(cfg.ui.fonts)-1]
}

config_move_font_up :: proc(cfg: ^Config, index: int) {
	if index == 0 do return
	src := index
	dst := index-1
	cfg.ui.fonts[dst].name_buf, cfg.ui.fonts[src].name_buf = 
		cfg.ui.fonts[src].name_buf, cfg.ui.fonts[dst].name_buf
}

config_move_font_down :: proc(cfg: ^Config, index: int) {
	if index == len(cfg.ui.fonts)-1 do return
	src := index
	dst := index+1
	cfg.ui.fonts[dst].name_buf, cfg.ui.fonts[src].name_buf = 
		cfg.ui.fonts[src].name_buf, cfg.ui.fonts[dst].name_buf
}

config_load :: proc(cfg_out: ^Config, path: string, allocator: mem.Allocator) -> (error: Error) {
	temp: Config
	data := os.read_entire_file_from_path(path, context.allocator) or_return
	defer delete(data)

	json.unmarshal(data, &temp, allocator=allocator) or_return

	copy(temp.ui.background_buf[:], string(temp.ui.background))
	delete(temp.ui.background)
	copy(temp.ui.default_theme_buf[:], string(temp.ui.default_theme))
	delete(temp.ui.default_theme)
	for &f, i in temp.ui.fonts {
		set_cstring_buf(temp.ui.fonts_buf[i].name_buf[:], string(f.name))
		delete(f.name)
	}
	delete(temp.ui.fonts)

	cfg_out^ = temp
	config_init_buffers(cfg_out)

	return
}

config_save :: proc(cfg: Config, path: string) -> (error: Error) {
	opt := json.Marshal_Options {
		pretty = true,
		use_enum_names = true,
	}

	data := json.marshal(cfg, opt) or_return
	defer delete(data)
	file := os.create(path) or_return
	defer os.close(file)
	os.write(file, data)
	return
}
