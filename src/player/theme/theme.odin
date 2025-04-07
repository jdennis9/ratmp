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
package theme;

import "core:path/filepath";
import "core:os";
import "core:fmt";
import "core:strings";
import "core:encoding/ini";
import "core:strconv";
import "core:slice";

import imgui "../../libs/odin-imgui";

import "../system_paths";
import "../util";
import "../prefs";

@private
theme_folder_path: string;

@private
this: struct {
	current_theme: [128]u8,
	scanned_themes: [dynamic]cstring,
};

init :: proc() {
	theme_folder_path = filepath.join({system_paths.DATA_DIR, "themes"});

	if !os.exists(theme_folder_path) {
		os.make_directory(theme_folder_path);
	}

	refresh_themes();

	load(prefs.get_string(.Theme));

	style := imgui.GetStyle();
	style.FrameBorderSize = 1;
}

shutdown :: proc() {
	delete(theme_folder_path);
}

get_current :: proc() -> cstring {
	return cstring(raw_data(this.current_theme[:]));
}

get_list :: proc() -> []cstring {
	return this.scanned_themes[:];
}

refresh_themes :: proc() {
	iterator :: proc(fullpath: string, is_folder: bool, _: rawptr) {
		stem := filepath.short_stem(filepath.base(fullpath));
		if stem == "" {return}
		s := strings.clone_to_cstring(stem);
		append(&this.scanned_themes, s);
	}

	for str in this.scanned_themes {
		delete(str);
	}

	clear(&this.scanned_themes);
	util.for_each_file_in_folder(theme_folder_path, iterator, nil);
}

format_theme_path :: proc(name: string) -> string {
	buf: [128]u8;
	filename := fmt.bprint(buf[:], name, ".ini", sep="");
	return filepath.join({theme_folder_path, filename});
}

exists :: proc(name: string) -> bool {
	for other in this.scanned_themes {
		if string(other) == name {
			return true;
		}
	}

	return false;
}

// Name of the theme, not path!
load :: proc(name: string) -> bool {
	imgui.StyleColorsDark();
	style := imgui.GetStyle();
	
	path := format_theme_path(name);
	defer delete(path);
	
	m, map_error := ini.load_map_from_path(path, context.allocator) or_return;
	defer ini.delete_map(m);

	load_style :: proc(m: ini.Map, style: ^imgui.Style) -> bool {
		section := m["Style"] or_return;
		borders, have_borders := section["FrameBorders"];
		if have_borders {
			val := strconv.parse_int(borders) or_else 0;
			if val > 0 {
				style.FrameBorderSize = 1;
			}
			else {
				style.FrameBorderSize = 0;
			}
		}

		return true;
	}

	load_colors :: proc(m: ini.Map, style: ^imgui.Style) -> bool {
		section := m["Colors"] or_return;
		
		for col in imgui.Col {
			if col == .COUNT {break}
			col_name := imgui.GetStyleColorName(col);
			col_value := section[string(col_name)] or_continue;
			components := strings.split(col_value, ",") or_continue;
			defer delete(components);
			if len(components) != 4 {continue}
			style.Colors[col].r = strconv.parse_f32(components[0]) or_else 0;
			style.Colors[col].g = strconv.parse_f32(components[1]) or_else 0;
			style.Colors[col].b = strconv.parse_f32(components[2]) or_else 0;
			style.Colors[col].a = strconv.parse_f32(components[3]) or_else 1;
		}

		return true;
	}

	load_style(m, style);
	load_colors(m, style);

	slice.fill(this.current_theme[:], 0);
	copy(this.current_theme[:len(this.current_theme)-1], name);
	return true;
}

save :: proc(name: string) {
	path := format_theme_path(name);
	style := imgui.GetStyle();
	defer delete(path);
	fd, open_error := util.overwrite_file(path);
	if open_error != nil {
		return;
	}

	fmt.fprintln(fd, "[Style]");
	fmt.fprintln(fd, "FrameBorders=", int(style.FrameBorderSize > 0), sep="");

	fmt.fprintln(fd, "[Colors]");
	for col in imgui.Col {
		if col == .COUNT {break}
		col_name := imgui.GetStyleColorName(col);
		v := style.Colors[col];
		fmt.fprintln(
			fd, col_name, "=",
			v.r, ",", v.g, ",", v.b, ",", v.a,  sep=""
		);
	}
}
