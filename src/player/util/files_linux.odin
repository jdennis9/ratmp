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

import "core:strings"
import "core:sys/posix"
import "core:c/libc"
import "core:slice"
import "core:log"

for_each_file_in_dialog :: proc(title: cstring, iterator: File_Iterator, 
	iterator_data: rawptr, select_folders := false
) -> int {
	buf: [512]u8
	fp: ^posix.FILE
	if select_folders {
		fp = posix.popen("zenity --file-selection --directory --multiple --separator=\"\n\"", "r")
	}
	else {
		fp = posix.popen("zenity --file-selection --multiple --separator=\"\n\"", "r")
	}

	if fp == nil {
		return 0
	}
	defer posix.pclose(fp)
	
	for libc.fgets(raw_data(buf[:511]), 512, fp) != nil {
		cstr := cstring(raw_data(buf[:]))
		log.debug(cstr)
		length := len(cstr)
		if length == 0 {continue}
		// Remove \n from end of string
		buf[length-1] = 0

		str := strings.clone_from_cstring(cstr)
		defer delete(str)

		iterator(str, select_folders, iterator_data)

		slice.fill(buf[:], 0)
	}

	return 0
}

open_file_dialog :: proc(out: []u8) -> (file: string, ok: bool) {
	buf: [512]u8
	fp := posix.popen("zenity --file-selection", "r")
	if fp == nil {log.error("popen failed"); return}
	defer posix.pclose(fp)

	if libc.fgets(&buf[0], auto_cast(len(buf)-1), fp) == nil {
		log.error("fgets failed")
		return
	}
	else if buf[0] == '\n' {
		log.error("No file")
		return
	}
	else {
		n := len(cstring(&buf[0]))
		buf[n-1] = 0
	}

	copy_cstring(out, cstring(&buf[0]))
	ok = true
	return
}
