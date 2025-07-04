#+private
package client

import "core:encoding/ini"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:log"
import "core:os"
import "core:fmt"

import "src:sys"

import imgui "src:thirdparty/odin-imgui"

// Enums work too
Settings_String :: [64]u8
Settings_Path :: [512]u8
Settings_Int :: int
Settings_Float :: f32
Settings_Bool :: bool
// String format: <name>:<size>
Settings_Font :: struct {
	name: [56]u8,
	size: int,
}
Settings_Fonts :: [sys.Font_Language]Settings_Font

Settings :: struct {
	theme: Settings_String,
	background: Settings_Path,
	crop_album_art: bool,
	fonts: Settings_Fonts,
	spectrum_bands: int,
	spectrum_mode: _Spectrum_Display_Mode,
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
			case Settings_Bool:
				(cast(^Settings_Bool) field_ptr)^ = value == "true"
			case Settings_Int:
				val := strconv.parse_int(value) or_else 0
				(cast(^Settings_Int) field_ptr)^ = val
			case Settings_String:
				str := cast(^Settings_String) field_ptr
				copy(str^[:len(Settings_String) - 1], value)
			case Settings_Path:
				path := cast(^Settings_Path) field_ptr
				copy(path^[:len(Settings_Path) - 1], value)
			case [sys.Font_Language]Settings_Font:
				if len(key_parts) == 1 {
					break
				}
				enum_val := reflect.enum_from_name(sys.Font_Language, key_parts[1]) or_break
				font := &settings.fonts[auto_cast enum_val]
				value_parts := strings.split(value, ":")
				defer delete(value_parts)

				if len(value_parts) < 2 {
					break
				}

				copy(font.name[:len(font.name)-1], value_parts[0])
				font.size = strconv.parse_int(value_parts[1]) or_else 0
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

	if os.exists(path) {os.remove(path)}
	f, file_error := os.open(path, os.O_WRONLY | os.O_CREATE)
	if file_error != nil {log.error(file_error); return false}
	defer os.close(f)

	fmt.fprintln(f, "[settings]")

	for field_index in 0..<ti.field_count {
		field := reflect.struct_field_at(Settings, auto_cast field_index)
		field_data := reflect.struct_field_value(settings^, field)
		field_ptr, _ := reflect.any_data(field_data)
		field_type := reflect.type_info_base(field.type)

		#partial switch type in field_type.variant {
			case reflect.Type_Info_Enumerated_Array:
				elem_type := reflect.type_info_base(type.elem)
				enum_type := reflect.type_info_base(type.index).variant.(reflect.Type_Info_Enum) or_break
				is_fonts := reflect.are_types_identical(type.elem, type_info_of(Settings_Font))

				for enum_index_name, value_index in enum_type.names {
					fmt.fprintf(f, "%s.%s = ", field.name, enum_index_name)
					if is_fonts {
						font := (cast([^]Settings_Font)field_ptr)[enum_type.values[value_index]]
						fmt.fprintf(f, "%s:%d\n", cstring(&font.name[0]), font.size)
					}
				}

			case reflect.Type_Info_Float, reflect.Type_Info_Boolean, reflect.Type_Info_Integer, reflect.Type_Info_Enum:
				fmt.fprintln(f, field.name, "=", field_data)
			
			case reflect.Type_Info_Array:
				elem := reflect.type_info_base(type.elem)

				if elem.id == typeid_of(u8) {
					str := cstring(cast([^]u8) field_ptr)
					fmt.fprintln(f, field.name, "=", str)
				}				
		}
	}

	return true
}

Settings_Editor :: struct {
}

show_settings_editor :: proc(cl: ^Client) {
	state := &cl.settings_editor
	settings := &cl.settings
	system_fonts := sys.get_font_list()

	font_selector :: proc(font: ^Settings_Font, system_fonts: []sys.Font_Handle) {
		imgui.PushIDPtr(font)
		defer imgui.PopID()

		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		if imgui.BeginCombo("##select_font", cstring(&font.name[0])) {
			for &sys_font in system_fonts {
				if imgui.Selectable(cstring(&sys_font.name[0]), false) {
					for &c in font.name {c = 0}
					copy(font.name[:len(font.name)-1], sys_font.name[:])
				}
			}
			imgui.EndCombo()
		}
	}

	if imgui.Button("Apply") {
		cl.want_apply_settings = true
	}

	if imgui.CollapsingHeader("Fonts") {
		if imgui.BeginTable("##font_table", 3, imgui.TableFlags_SizingStretchSame) {
			row :: proc(lang: string, font: ^Settings_Font, system_fonts: []sys.Font_Handle) {
				imgui.TableNextRow()
				imgui.PushIDPtr(font)
				defer imgui.PopID()
				if imgui.TableSetColumnIndex(0) {_native_text_unformatted(lang)}
				if imgui.TableSetColumnIndex(1) {
					font_selector(font, system_fonts)
				}
				if imgui.TableSetColumnIndex(2) {
					font.size = clamp(font.size, 9, 48)
					val := i32(font.size)
					imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
					if imgui.DragInt("##size", &val, 0.1, 9, 48) {
						font.size = int(val)
					}
				}
			}

			row("Icons", &settings.fonts[.Icons], system_fonts)
			row("Chinese Full", &settings.fonts[.ChineseFull], system_fonts)
			row("Chinese Simplified", &settings.fonts[.ChineseSimplifiedCommon], system_fonts)
			row("Cyrillic", &settings.fonts[.Cyrillic], system_fonts)
			row("Greek", &settings.fonts[.Greek], system_fonts)
			row("English", &settings.fonts[.English], system_fonts)
			row("Japanese", &settings.fonts[.Japanese], system_fonts)

			imgui.EndTable()
		}
	}
}

apply_settings :: proc(cl: ^Client) {
	load_fonts_from_settings(cl, 1)
}
