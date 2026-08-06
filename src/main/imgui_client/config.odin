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
#+private file
package client

import "core:strings"
import "core:path/filepath"
import lib "src:main/library"
import "core:strconv"
import "core:fmt"
import "src:main/sys"
import "src:main/player"
import "core:os"
import "core:encoding/ini"
import "core:log"
import "src:main/shared"
import "core:mem"
import imgui "src:thirdparty/odin-imgui"
import "src:imx"

@private
User_Config :: struct {
	ui:       UI_Config,
	playback: player.Config,
	library:  lib.Config,
	fonts:    [dynamic; 32]sys.System_Font,
}

@private
USER_CONFIG_DEFAULTS :: User_Config {
	ui = {
		font_size = 16,
	},
	playback = player.CONFIG_DEFAULTS,
}

_config: User_Config = USER_CONFIG_DEFAULTS

@private
get_user_config :: proc() -> User_Config {
	return _config
}

// @NOTE: Also frees memory associated with loaded config
@private
set_user_config :: proc(cfg: User_Config) {
	_config = cfg
}

_get_path :: proc(allocator: mem.Allocator) -> string {
	str, _ := filepath.join({get_config_path(), "settings.ini"})
	return str
}

@private
load_user_config :: proc() -> (error: shared.Error) {
	c := &_config
	c^ = USER_CONFIG_DEFAULTS
	temp_allocator := get_frame_allocator()

	path := _get_path(temp_allocator)

	m, load_error := ini.load_map_from_path(path, temp_allocator) or_return

	if load_error != nil  {
		log.error(load_error)
		return false
	}

	if sect, found := m["UI"]; found {
		for k, v in sect {
			switch k {
			case "BackgroundImage":
				copy(c.ui.background_image[:len(c.ui.background_image)-1], v)
			case "DefaultTheme":
				copy(c.ui.default_theme[:len(c.ui.default_theme)-1], v)
			case "FontSize":
				c.ui.font_size = strconv.parse_f32(v) or_break
			case "Fonts":
				fonts := strings.split(v, ";", temp_allocator)
				for f in fonts[:min(cap(c.ui.fonts), len(fonts))] {
					sf := sys.font_from_name(get_system_fonts(), strings.trim_space(f)) or_continue
					append(&c.ui.fonts, sf)
				}
			}
		}
	}

	if sect, found := m["Playback"]; found {
		c.playback = player.parse_config(sect)
	}

	if sect, found := m["Library"]; found {
		c.library = lib.parse_config(sect)
	}

	apply_user_config()

	return
}

@private
save_user_config :: proc() -> shared.Error {
	frame_allocator_guard()

	c := &_config
	temp_allocator := get_frame_allocator()

	path := _get_path(temp_allocator)

	file := os.create(path) or_return
	defer os.close(file)

	m: ini.Map
	defer delete(m)

	ui: map[string]string
	defer delete(ui)
	ui["BackgroundImage"] = shared.string_from_array(c.ui.background_image[:])
	ui["DefaultTheme"]    = shared.string_from_array(c.ui.default_theme[:])
	ui["FontSize"]        = fmt.aprint(c.ui.font_size, allocator=temp_allocator)
	// Fonts
	{
		sb: strings.Builder
		strings.builder_init(&sb, temp_allocator)
		defer strings.builder_destroy(&sb)

		for font in c.ui.fonts {
			strings.write_string(&sb, string(font.name))
			strings.write_rune(&sb, ';')
		}

		ui["Fonts"] = strings.to_string(sb)
	}

	playback: map[string]string
	defer delete(playback)
	player.write_config(c.playback, &playback, temp_allocator)

	library: map[string]string
	defer delete(library)
	lib.write_config(c.library, &library, temp_allocator)

	m["UI"]       = ui
	m["Playback"] = playback
	m["Library"]  = library

	map_string := ini.save_map_to_string(m, temp_allocator)

	os.write(file, transmute([]byte) map_string)
	
	apply_user_config()

	return nil
}

@private
apply_user_config :: proc() {
	c := _config
	ui_apply_config(&c.ui)
	player.apply_config(c.playback)
	lib.apply_config(c.library)
}

@private
config_editor_window_proc :: proc(ev: UI_Window_Event) -> bool {
	if ev.type != .Show do return false
	frame_allocator_guard()

	changed := false
	c := &_config
	temp_allocator := get_frame_allocator()

	if imgui.Button("Save") {
		path, _ := filepath.join({get_config_path(), "settings.ini"}, temp_allocator)
		save_user_config()
	}

	imx.title_text("UI")
	// @TODO: File selects for these
	changed |= imx.input_text("Background image", c.ui.background_image[:])
	changed |= imx.input_text("Default theme",    c.ui.default_theme[:])
	changed |= imgui.DragFloat("Font size", &c.ui.font_size, 0.1, 9, 48, "%.0f", {.ClampOnInput})

	// Fonts list
	if imgui.BeginListBox("##fonts") {
		defer imgui.EndListBox()

		imgui.SetItemTooltip("Fonts are prioritized from top to bottom.")

		font_items_loop: for f, i in c.ui.fonts {
			imgui.PushIDInt(auto_cast i)
			defer imgui.PopID()
			
			imgui.MenuItem(f.name)
			if imgui.BeginPopupContextItem() {
				defer imgui.EndPopup()

				if imgui.MenuItem("Remove") {
					ordered_remove(&c.ui.fonts, i)
					break font_items_loop
				}

				if imgui.MenuItem("Move up", enabled = i >= 0) {
					c.ui.fonts[i], c.ui.fonts[i-1] = c.ui.fonts[i-1], c.ui.fonts[i]
				}

				if imgui.MenuItem("Move down", enabled = i < len(c.ui.fonts)-1) {
					c.ui.fonts[i], c.ui.fonts[i+1] = c.ui.fonts[i+1], c.ui.fonts[i]
				}
			}
		}
	}

	// Add font
	if len(c.ui.fonts) == cap(c.ui.fonts) {
		imgui.TextDisabled("Maximum fonts used")
	}
	else if imgui.BeginCombo("##add_font", "Add font") {
		defer imgui.EndCombo()

		for f in get_system_fonts() {
			if imgui.MenuItem(f.name) {
				append(&c.ui.fonts, f)
			}
		}
	}

	imx.title_text("Playback")
	changed |= imgui.Checkbox("Enable ReplayGain", &c.playback.enable_replaygain)
	changed |= imx.select_enum("ReplayGain preference", &c.playback.replaygain_preference)
	changed |= imgui.DragFloat("Preamp gain for ReplayGain", &c.playback.replaygain_pregain, 0.1, -12, 12, "%.0f dB")

	imx.title_text("Library")
	changed |= imgui.Checkbox("Prefer folder cover art", &c.library.prefer_folder_cover_art)
	imgui.SetItemTooltip("When cover art exists in the same folder as a track, prefer using that over the art embedded in the track metadata.")

	return true
}

