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

import "base:runtime"
import "core:encoding/ini"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:log"
import "core:os/os2"
import "core:os"
import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

import "src:sys"

import "imx"


// Enums work too
Settings_String :: [64]u8
Settings_Path :: [512]u8
Settings_Float :: f32
// String format: <name>:<size>
Settings_Font :: struct {
	name: [56]u8,
}

Close_Policy :: enum {
	AlwaysAsk,
	MinimizeToTray,
	Exit,
}

Settings :: struct {
	theme: Settings_String,
	background: Settings_Path,
	fonts: [dynamic]Settings_Font,
	close_policy: Close_Policy,
	font_size: int,

	// Not saved
	serial: uint,
}

load_settings :: proc(settings: ^Settings, path: string) -> bool {
	data, parse_error, _ := ini.load_map_from_path(path, context.allocator)
	if parse_error != nil {
		log.error(parse_error)
		return false
	}
	defer ini.delete_map(data)

	section := data["settings"] or_return
	for key, value in section {
		key_parts := strings.split(key, ".")
		defer delete(key_parts)

		field := reflect.struct_field_by_name(Settings, key_parts[0])
		if field.type == nil {continue}
		field_val := reflect.struct_field_value(settings^, field)
		field_ptr, _ := reflect.any_data(field_val)

		switch field.type.id {
			case bool:
				(cast(^bool) field_ptr)^ = value == "true"
			case int:
				val := strconv.parse_int(value) or_else 0
				(cast(^int) field_ptr)^ = val
			case Settings_String:
				str := cast(^Settings_String) field_ptr
				copy(str^[:len(Settings_String) - 1], value)
			case Settings_Path:
				path := cast(^Settings_Path) field_ptr
				copy(path^[:len(Settings_Path) - 1], value)
			case [dynamic]Settings_Font:
				output := cast(^[dynamic]Settings_Font) field_ptr

				fonts := strings.split(value, ",")
				defer delete(fonts)

				for font in fonts {
					f: Settings_Font
					if font == "" do continue
					copy(f.name[:len(f.name)-1], font)
					append(output, f)
				}

			case:
				field_enum := reflect.type_info_base(field.type)
				enum_type := field_enum.variant.(reflect.Type_Info_Enum) or_break
				enum_val := reflect.enum_from_name_any(field_enum.id, value) or_break
				assert(enum_type.base.id == int)
				(cast(^int) field_ptr)^ = int(enum_val)
		}
	}

	return true
}

save_settings :: proc(settings: ^Settings, path: string) -> bool {
	settings_info := type_info_of(Settings)
	ti := reflect.type_info_base(settings_info).variant.(reflect.Type_Info_Struct)

	if os2.exists(path) {os2.remove(path)}
	f_os2, file_error := os2.create(path)
	if file_error != nil {log.error(file_error); return false}
	defer os2.close(f_os2)

	f := cast(os.Handle) os2.fd(f_os2)

	fmt.fprintln(f, "[settings]")

	for field_index in 0..<ti.field_count {
		field := reflect.struct_field_at(Settings, auto_cast field_index)
		field_data := reflect.struct_field_value(settings^, field)
		field_ptr, _ := reflect.any_data(field_data)
		field_type := reflect.type_info_base(field.type)

		if field.name == "serial" do continue

		#partial switch type in field_type.variant {
			/*case reflect.Type_Info_Enumerated_Array:
				enum_type := reflect.type_info_base(type.index).variant.(reflect.Type_Info_Enum) or_break
				is_fonts := reflect.are_types_identical(type.elem, type_info_of(Settings_Font))

				for enum_index_name, value_index in enum_type.names {
					fmt.fprintf(f, "%s.%s = ", field.name, enum_index_name)
					if is_fonts {
						font := (cast([^]Settings_Font)field_ptr)[enum_type.values[value_index]]
						fmt.fprintf(f, "%s:%d\n", cstring(&font.name[0]), font.size)
					}
				}*/
			case reflect.Type_Info_Dynamic_Array:
				elem_type := type.elem
				
				switch elem_type.id {
					case Settings_Font:
						fmt.fprint(f, field.name, "=", sep="")
						array := cast(^[dynamic]Settings_Font) field_ptr
						log.debug(array)
						for &font in array^ {
							fmt.println(cstring(&font.name[0]))
							fmt.fprint(f, cstring(&font.name[0]), ",", sep="")
						}
						fmt.fprintln(f)
				}

			case reflect.Type_Info_Array:
				elem := reflect.type_info_base(type.elem)

				if elem.id == typeid_of(u8) {
					str := cstring(cast([^]u8) field_ptr)
					fmt.fprintln(f, field.name, "=", str)
				}
			case:
				fmt.fprintln(f, field.name, "=", field_data)			
		}
	}

	return true
}

Settings_Editor :: struct {
	font_input: Settings_Font,
}

show_settings_editor :: proc(cl: ^Client) {
	settings := &cl.settings
	system_fonts := sys.get_font_list()
	state := &cl.windows.settings
	settings_changed := false

	defer if settings_changed do settings.serial += 1

	font_selector :: proc(font: ^Settings_Font, system_fonts: []sys.Font_Handle) -> (selected: bool) {
		imgui.PushIDPtr(font)
		defer imgui.PopID()

		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)

		if imgui.BeginCombo("##select_font", "Add a font") {
			for &sys_font in system_fonts {
				if imgui.Selectable(cstring(&sys_font.name[0]), false) {
					for &c in font.name {c = 0}
					copy(font.name[:len(font.name)-1], sys_font.name[:])
					selected = true
				}
			}
			imgui.EndCombo()
		}

		return
	}

	begin_settings_table :: proc(str_id: cstring) -> bool {
		if imgui.BeginTable(str_id, 3, imgui.TableFlags_SizingStretchSame|imgui.TableFlags_RowBg) {
			//imgui.TableSetupColumn("##name", {}, 0.4)
			//imgui.TableSetupColumn("##value", {}, 0.4)
			//imgui.TableSetupColumn("##misc", {}, 0.2)
			return true
		}
		
		return false
	}

	path_row :: proc(
		name: string, path: ^Settings_Path, browse_dialog: ^sys.File_Dialog_State,
		file_type: sys.File_Type
	) -> (changed: bool) {
		imgui.TableNextRow()
		imgui.PushIDPtr(path)
		defer imgui.PopID()
		if imgui.TableSetColumnIndex(0) {imx.text_unformatted(name)}
		if imgui.TableSetColumnIndex(1) {
			imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
			changed |= imgui.InputText("##path", cstring(&path^[0]), len(Settings_Path))
		}
		if imgui.TableSetColumnIndex(2) {
			if imgui.Button("Browse") {
				sys.open_async_file_dialog(browse_dialog, file_type, {})
			}
			imgui.SameLine()
			if imgui.Button("Clear") {
				for &c in path^ do c = 0
				changed = true
			}
		}

		return
	}

	enum_picker_row :: proc(name: string, $T: typeid, val: ^T, names: [$E]cstring) -> (picked: bool) {
		assert(len(names) == len(T))
		imgui.TableNextRow()
		imgui.PushIDPtr(val)
		defer imgui.PopID()
		if imgui.TableSetColumnIndex(0) {imx.text_unformatted(name)}
		if imgui.TableSetColumnIndex(1) {
			if imgui.BeginCombo("##combo", names[val^]) {
				for enum_val in reflect.enum_field_values(T) {
					if imgui.Selectable(names[auto_cast enum_val]) {
						val^ = auto_cast enum_val
						picked = true
					}
				}
				imgui.EndCombo()
			}
		}

		return picked
	}

	if imgui.Button("Apply") {
		cl.want_apply_settings = true
		save_settings(settings, cl.paths.settings)
	}

	if imgui.CollapsingHeader("Appearance", {.DefaultOpen}) {
		if begin_settings_table("##appearance") {
			settings_changed |= path_row("Background", &settings.background, &cl.dialogs.set_background, .Image)
		
			imgui.TableNextRow()
			if imgui.TableSetColumnIndex(0) {imx.text_unformatted("Default theme")}
			if imgui.TableSetColumnIndex(1) {
				imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
				if imgui.BeginCombo("Default theme", cstring(&settings.theme[0])) {
					for theme in cl.theme_names {
						if imgui.Selectable(theme) {
							for &c in settings.theme do c = 0
							copy(settings.theme[:len(settings.theme)-1], string(theme))
							settings_changed = true
						}
					}
					imgui.EndCombo()
				}
			}

			imgui.EndTable()
		}
	}

	if imgui.CollapsingHeader("Behaviour", {.DefaultOpen}) {
		if begin_settings_table("##behaviour") {
			settings_changed |= enum_picker_row(
				"Close policy", Close_Policy, &settings.close_policy, [Close_Policy]cstring {
				.AlwaysAsk = "Always ask",
				.Exit = "Exit",
				.MinimizeToTray = "Minimize to tray",
			})
			imgui.EndTable()
		}
	}

	if imgui.CollapsingHeader("Fonts", {.DefaultOpen}) {
		remove_font: Maybe(int)
		move_font_up: Maybe(int)
		move_font_down: Maybe(int)

		font_size := i32(settings.font_size)

		if imgui.DragInt("Font size", &font_size, 0.3, 8, 32) do settings.font_size = int(font_size)

		if imgui.BeginChild("##fonts", {}, {.AlwaysAutoResize, .AutoResizeY}) {
			for &font, index in settings.fonts {
				imgui.Selectable(cstring(&font.name[0]))

				if imgui.BeginPopupContextItem() {
					if index != 0 && imgui.MenuItem("Move up") do move_font_up = index
					if index < (len(settings.fonts)-1) && imgui.MenuItem("Move down") do move_font_down = index
					if imgui.MenuItem("Remove") do remove_font = index
					imgui.EndPopup()
				}
			}

			imgui.EndChild()
		}

		if remove_font != nil {
			ordered_remove(&settings.fonts, remove_font.?)
			settings_changed = true
		}
		else if move_font_up != nil {
			a := move_font_up.?
			b := a - 1
			assert(b >= 0)
			settings.fonts[a], settings.fonts[b] = settings.fonts[b], settings.fonts[a]
		}
		else if move_font_down != nil {
			a := move_font_down.?
			b := a + 1
			assert(b < len(settings.fonts))
			settings.fonts[a], settings.fonts[b] = settings.fonts[b], settings.fonts[a]
		}

		if font_selector(&state.font_input, system_fonts) {
			append(&settings.fonts, state.font_input)
			state.font_input = {}
			settings_changed = true
		}
	}
}

apply_settings :: proc(cl: ^Client) {
	theme: Theme
	settings := cl.settings
	theme_name := string(cstring(&settings.theme[0]))
	style := imgui.GetStyle()

	cl.font_size = f32(settings.font_size)

	load_fonts_from_settings(cl, 1)
	theme_load_from_name(cl^, &theme, theme_name)
	set_theme(cl, theme, theme_name)
	set_background(cl, string(cstring(&settings.background[0])))
}
