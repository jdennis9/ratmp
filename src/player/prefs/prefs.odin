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
package prefs;

import "core:encoding/ini";
import "core:path/filepath";
import "core:os";
import "core:strings";
import "core:strconv";
import "core:fmt";
import "core:bytes";
import "core:log";

import "player:system_paths";
import "player:util";
import "player:signal";

FONT_SIZE_MIN :: 8
FONT_SIZE_MAX :: 24

String_Buffer :: [384]u8;

StringID :: enum {
	Font,
	Background,
	Theme,
	PlaybackDevice,
};

NumberID :: enum {
	FontSize,
	IconSize,
};

ChoiceID :: enum {
	ClosePolicy,
	EnableWindowsMediaControls,
};

Prefs :: struct {
	strings: [StringID]String_Buffer,
	numbers: [NumberID]int,
	choices: [ChoiceID]int,
};

prefs: Prefs;

NUMBER_INFO := [NumberID]struct{name: string, min, max, def: int} {
	.FontSize = {"FontSize", 8, 24, 13},
	.IconSize = {"IconSize", 8, 24, 12},
};

STRING_INFO := [StringID]struct{name: string} {
	.Background = {"Background"},
	.Font = {"Font"},
	.Theme = {"Theme"},
	.PlaybackDevice = {"PlaybackDevice"},
};

Choice_Value :: struct {
	name: cstring,
	ini_name: cstring,
	value: int,
};

CLOSE_POLICY_ALWAYS_ASK :: 0;
CLOSE_POLICY_MINIMIZE_TO_TRAY :: 1;
CLOSE_POLICY_CLOSE :: 2;

CHOICE_INFO := [ChoiceID]struct{name: string, def: int, values: []Choice_Value} {
	.ClosePolicy = {
		name = "ClosePolicy",
		def = CLOSE_POLICY_ALWAYS_ASK,
		values = {
			{"Always ask", "AlwaysAsk", CLOSE_POLICY_ALWAYS_ASK},
			{"Minimize to tray", "MinimizeToTray", CLOSE_POLICY_MINIMIZE_TO_TRAY},
			{"Close", "Close", CLOSE_POLICY_CLOSE},
		},
	},
	.EnableWindowsMediaControls = {
		name = "EnableWindowsMediaControls",
		def = 1,
		values = {
			{"No", "No", 0},
			{"Yes", "Yes", 1},
		},
	},
};

@private
Section :: struct {
	name: string,
	strings: []StringID,
	numbers: []NumberID,
	choices: []ChoiceID,
};

@private
_sections := []Section {
	{
		name = "ui",
		strings = {.Font, .Background, .Theme},
		numbers = {.FontSize, .IconSize},
		choices = {.ClosePolicy},
	},
	{
		name = "playback",
		strings = {.PlaybackDevice},
	},
	{
		name = "windows",
		choices = {.EnableWindowsMediaControls},
	}
};

@private
_set_defaults :: proc() {
	for entry, index in NUMBER_INFO {
		prefs.numbers[index] = entry.def;
	}

	for entry, index in CHOICE_INFO {
		prefs.choices[index] = entry.def;
	}
}

get_string :: proc(str: StringID) -> string {
	return string(cstring(raw_data(prefs.strings[str][:])));
}

get_cstring :: proc(str: StringID) -> cstring {
	return cstring(raw_data(prefs.strings[str][:]));
}

load :: proc() {
	prefs_path := filepath.join({system_paths.CONFIG_DIR, "prefs.ini"});
	defer delete(prefs_path);
	
	_set_defaults();

	m, map_error, ok := ini.load_map_from_path(prefs_path, context.allocator);
	if !ok || map_error != nil {
		save();
		signal.post(.ApplyPrefs);
		return;
	}
	
	for section in _sections {
		section_map := m[section.name] or_continue;
		log.debug(section.name);

		for index in section.strings {
			value := section_map[STRING_INFO[index].name] or_continue;
			copy(prefs.strings[index][:len(String_Buffer)-1], value);
		}

		for index in section.numbers {
			value_string := section_map[NUMBER_INFO[index].name] or_continue;
			parsed := strconv.parse_i64(value_string) or_continue;
			prefs.numbers[index] = int(parsed);
		}

		for index in section.choices {
			value_string := section_map[CHOICE_INFO[index].name] or_continue;
			info := CHOICE_INFO[index];
			choice := info.def;

			for value in info.values {
				if value_string == string(value.ini_name) {
					choice = value.value;
					break;
				}
			}

			prefs.choices[index] = choice;
		}
	}
	
	_load_properties();
	signal.post(.ApplyPrefs);
}

save :: proc() {
	prefs_path := filepath.join({system_paths.CONFIG_DIR, "prefs.ini"});
	defer delete(prefs_path);

	fd, open_error := util.overwrite_file(prefs_path);
	if open_error != nil {return}
	defer os.close(fd);

	for section in _sections {
		fmt.fprintln(fd, "[", section.name, "]", sep = "");
		for str in section.strings {
			fmt.fprintln(fd, STRING_INFO[str].name, "=", cstring(raw_data(prefs.strings[str][:])), sep = "");
		}

		for number in section.numbers {
			fmt.fprintln(fd, NUMBER_INFO[number].name, "=", prefs.numbers[number], sep = "");
		}

		for choice in section.choices {
			info := CHOICE_INFO[choice];
			for value in info.values {
				if prefs.choices[choice] == value.value {
					fmt.fprintln(fd, CHOICE_INFO[choice].name, "=", value.ini_name, sep = "");
					break;
				}
			}
		}
	}

	_save_properties();
}
