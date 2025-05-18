#+private
package client

import "core:log"
import "core:thread"
import "core:os/os2"
import "core:path/filepath"

import "src:server"

_File_Iterator :: #type proc(path: string, is_folder: bool, data: rawptr)
_File_Type :: enum {
	Audio,
	Image,
	Font,
}

_File_Dialog_State :: struct {
	thread: ^thread.Thread,
	select_folders: bool,
	multiselect: bool,
	file_type: _File_Type,
	results: [dynamic]Path,
}

@(private="file")
_file_dialog_thread_proc :: proc(dialog_thread: ^thread.Thread) {
	state := cast(^_File_Dialog_State) dialog_thread.data

	iterator :: proc(path: string, is_folder: bool, data: rawptr) {
		state := cast(^_File_Dialog_State)data
		path_buf: Path
		server.copy_string_to_buf(path_buf[:], path)
		append(&state.results, path_buf)
	}

	for_each_file_in_dialog(nil, iterator, state, state.select_folders, state.multiselect, state.file_type)
}

_open_async_file_dialog :: proc(state: ^_File_Dialog_State, select_folders := true, multiselect := true, file_type := _File_Type.Audio) -> bool {
	if state.thread != nil {
		log.warn("Tried openning a file dialog in the background when there is already one running")
		return false
	}

	state.select_folders = select_folders
	state.multiselect = multiselect
	state.file_type = file_type
	state.thread = thread.create(_file_dialog_thread_proc)
	if state.thread == nil {return false}
	state.thread.data = state
	thread.start(state.thread)

	return true
}

_async_file_dialog_is_running :: proc(state: _File_Dialog_State) -> bool {return state.thread != nil}

// If files were selected, append them to the output array and destroy the dialog
_async_file_dialog_get_results :: proc(state: ^_File_Dialog_State, output: ^[dynamic]Path) -> bool {
	if state.thread == nil || !thread.is_done(state.thread) {return false}

	if len(state.results) == 0 {return false}

	for result in state.results {
		append(output, result)
	}

	thread.destroy(state.thread); state.thread = nil
	delete(state.results); state.results = nil

	return true
}

_Background_Scan :: struct {
	thread: ^thread.Thread,
	folders: [dynamic]Path,
	file_count: int,
	files_counted: bool,

	output: server.Track_Set,
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

			iter := os2.read_directory_iterator_create(dir)
			defer os2.read_directory_iterator_destroy(&iter)

			for {
				file, _ := os2.read_directory_iterator(&iter) or_break

				// @FixMe: Workaround for Odin os2 bug when decoding file names, 
				// remove when fix is released
				c := filepath.clean(file.fullpath)
				defer delete(c)
				if c == cleaned_path {continue}

				if file.type == .Regular &&  server.is_audio_file_supported(file.fullpath) {
					count += 1
				}
				else if file.type == .Directory {
					count += count_files(file.fullpath)
				}
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
		server.scan_directory_tracks(string(cstring(&folder[0])), &scan.output)
	}
}

_begin_background_scan :: proc(scan: ^_Background_Scan, input: []Path) {
	assert(len(scan.folders) == 0)
	scan.thread = thread.create(_background_scan_proc)
	scan.file_count = 0
	scan.files_counted = false
	scan.folders = nil
	scan.output = {}
	scan.thread.data = scan
	scan.thread.init_context = context

	resize(&scan.folders, len(input))
	for folder in input {
		append(&scan.folders, folder)
	}

	thread.start(scan.thread)
}

_background_scan_is_running :: proc(scan: _Background_Scan) -> bool {
	return scan.thread != nil && !thread.is_done(scan.thread)
}

_background_scan_wait_for_results :: proc(library: ^server.Library, scan: ^_Background_Scan) -> bool {
	if scan.thread != nil {
		thread.join(scan.thread)
		_background_scan_output_results(library, scan)
		return true
	}

	return false
}

_background_scan_output_results :: proc(library: ^server.Library, scan: ^_Background_Scan) -> bool {
	if scan.thread != nil && thread.is_done(scan.thread) {
		if library != nil {
			server.library_add_track_set(library, scan.output)
		}

		thread.destroy(scan.thread)
		delete(scan.folders)
		server.delete_track_set(&scan.output)
		scan^ = {}

		return true
	}

	return false
}
