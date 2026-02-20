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
package server

import "core:thread"
import "core:os/os2"
import "core:path/filepath"

_Background_Scan :: struct {
	thread: ^thread.Thread,
	folders: [dynamic]Path,
	file_count: int,
	files_counted: bool,

	output: Track_Set,

	on_complete: proc(),
}

@(private="file")
_background_scan_proc :: proc(scan_thread: ^thread.Thread) {
	scan := cast(^_Background_Scan) scan_thread.data

	count_files :: proc(path: string) -> int {	
		if os2.is_dir(path) {
			cleaned_path := filepath.clean(path)
			defer delete(cleaned_path)

			count: int
			dir, dir_error := os2.open(path)
			if dir_error != nil {return 0}
			defer os2.close(dir)

			files, read_error := os2.read_all_directory(dir, context.allocator)
			defer os2.file_info_slice_delete(files, context.allocator)

			if read_error != nil do return 0

			for file in files {
				if file.type == .Regular && is_audio_file_supported(file.fullpath) do count += 1
				else if file.type == .Directory do count += count_files(file.fullpath)
			}

			return count
		}
		else {
			return 1
		}
	}

	for &folder in scan.folders {
		scan.file_count += count_files(string(cstring(&folder[0])))
	}

	scan.files_counted = true

	for &folder in scan.folders {
		scan_directory_tracks(string(cstring(&folder[0])), &scan.output)
	}

	if scan.on_complete != nil {scan.on_complete()}
}

_begin_background_scan :: proc(scan: ^_Background_Scan, input: []Path, on_complete: proc()) {
	assert(len(scan.folders) == 0)
	scan.thread = thread.create(_background_scan_proc)
	scan.file_count = 0
	scan.files_counted = false
	scan.folders = nil
	scan.output = {}
	scan.thread.data = scan
	scan.thread.init_context = context
	scan.on_complete = on_complete

	reserve(&scan.folders, len(input))
	for folder in input {
		append(&scan.folders, folder)
	}

	thread.start(scan.thread)
}

_background_scan_is_running :: proc(scan: _Background_Scan) -> bool {
	return scan.thread != nil && !thread.is_done(scan.thread)
}

_background_scan_wait_for_results :: proc(library: ^Library, scan: ^_Background_Scan) -> bool {
	if scan.thread != nil {
		thread.join(scan.thread)
		_background_scan_output_results(library, scan)
		return true
	}

	return false
}

_background_scan_output_results :: proc(library: ^Library, scan: ^_Background_Scan) -> bool {
	if scan.thread != nil && thread.is_done(scan.thread) {
		if library != nil {
			library_add_track_set(library, scan.output)
		}

		thread.destroy(scan.thread)
		delete(scan.folders)
		track_set_delete(&scan.output)
		scan^ = {}

		return true
	}

	return false
}
