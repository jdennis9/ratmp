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
#+private
package main

import "core:sys/posix"
import "core:c/libc"

for_each_file_in_dialog :: proc(
	title:         cstring,
	file_proc:     File_Proc, 
	iterator_data: rawptr,
	file_type:     File_Type,
	flags:         File_Dialog_Flags,
) -> int {
	buf: [512]u8
	count: int
	select_folders := .SelectFolders in flags

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
		length := len(cstr)
		if length == 0 {continue}
		// Remove \n from end of string
		buf[length-1] = 0

		file_proc(string(cstr), select_folders, iterator_data)

		for &i in buf[:length] {i = 0}
		count += 1
	}

	return count
}

