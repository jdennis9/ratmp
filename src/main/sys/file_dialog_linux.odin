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
package sys

import "core:log"
import "core:os"
import "core:c/libc"
import "src:main/shared"
import "core:strings"
import "core:mem"


@require_results
show_file_dialog :: proc(
	params: File_Dialog_Params, results_allocator: mem.Allocator
) -> (results: []string, ok: bool) {
	cmd: [dynamic; 32]string

	append(&cmd, "zenity", "--file-selection")

	if params.select_multiple {
		append(&cmd, "--multiple")
	}

	if params.select_folders {
		append(&cmd, "--directory")
	}

	append(&cmd, "--separator=\"\n\"")

	proc_desc := os.Process_Desc {
		command = cmd[:],
	}

	state, stdout, stderr, error := os.process_exec(proc_desc, context.allocator)

	if error != nil {
		log.error(error)
		return
	}

	if stdout == nil do return
	res    := strings.clone(string(stdout), results_allocator)
	res     = strings.trim(res, "\n")
	results = strings.split(res, "\n", results_allocator)
	ok      = true

	return
}
