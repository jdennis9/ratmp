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
package system_paths

import "core:os"
import "core:path/filepath"

DATA_DIR: string
CONFIG_DIR: string

init_os_specific :: proc() {
	when ODIN_DEBUG {
		DATA_DIR = "."
		CONFIG_DIR = "."
	}
	else {
		config_home, config_home_found := os.lookup_env("XDG_CONFIG_HOME")
		defer if config_home_found {delete(config_home)}

		data_dir, data_dir_found := os.lookup_env("XDG_DATA_DIR")
		defer if data_dir_found {delete(data_dir)}

		home := os.get_env("HOME")
		defer delete(home)

		if data_dir_found {
			DATA_DIR = filepath.join({data_dir, "zno"})
		}
		else {
			DATA_DIR = filepath.join({home, ".local", "share", "zno"})
		}

		if config_home_found {
			CONFIG_DIR = filepath.join({config_home, "zno"})
		}
		else {
			CONFIG_DIR = filepath.join({home, ".config", "zno"})
		}

		if !os.exists(DATA_DIR) {
			os.make_directory(DATA_DIR)
		}

		if !os.exists(CONFIG_DIR) {
			os.make_directory(CONFIG_DIR)
		}
	}
}
