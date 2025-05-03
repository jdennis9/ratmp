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
package util

import "core:os"
import "core:log"

File_Iterator :: #type proc(path: string, is_folder: bool, data: rawptr)

for_each_file_in_folder :: proc(path: string, iterator: File_Iterator, iterator_data: rawptr) -> bool {
	dir, open_err := os.open(path)
	if open_err != os.ERROR_NONE {
		log.error(os.error_string(open_err), "Failed to open directory", path)
		return false
	}
	defer os.close(dir)

	files, read_err := os.read_dir(dir, 0)
	if read_err != os.ERROR_NONE {
		log.error(os.error_string(read_err), "Failed to read from directory", path)
		return false
	}
	defer os.file_info_slice_delete(files)

	for f in files {
		iterator(f.fullpath, f.is_dir, iterator_data)
	}

	return true
}

overwrite_file :: proc(path: string) -> (handle: os.Handle, error: os.Error) {
	when ODIN_OS == .Windows {
		handle, error = os.open(path, os.O_TRUNC|os.O_CREATE|os.O_WRONLY)
	}
	else {
		handle, error = os.open(path, os.O_TRUNC|os.O_CREATE|os.O_WRONLY, os.S_IRUSR|os.S_IWUSR|os.S_IROTH)
	}

	if error != nil {
		log.error("Failed to open file", path, "for writing")
	}

	return
}
