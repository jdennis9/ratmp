#+private
package ui

import "core:thread"
import "core:log"

import "player:util"

_File_Dialog_State :: struct {
	thread: ^thread.Thread,
	select_folders: bool,
	results: [dynamic]_Path,
}

@(private="file")
_file_dialog_thread_proc :: proc(dialog_thread: ^thread.Thread) {
	state := cast(^_File_Dialog_State) dialog_thread.data

	iterator :: proc(path: string, is_folder: bool, data: rawptr) {
		state := cast(^_File_Dialog_State)data
		path_buf: _Path
		util.copy_string_to_buf(path_buf[:], path)
		append(&state.results, path_buf)
	}

	util.for_each_file_in_dialog(nil, iterator, state, state.select_folders)
}

_open_async_file_dialog :: proc(state: ^_File_Dialog_State, select_folders := true) -> bool {
	if state.thread != nil {
		log.warn("Tried openning a file dialog in the background when there is already one running")
		return false
	}

	state.select_folders = select_folders
	state.thread = thread.create(_file_dialog_thread_proc)
	if state.thread == nil {return false}
	state.thread.data = state
	thread.start(state.thread)

	return true
}

_async_file_dialog_is_running :: proc(state: _File_Dialog_State) -> bool {return state.thread != nil}

// If files were selected, append them to the output array and destroy the dialog
_async_file_dialog_get_results :: proc(state: ^_File_Dialog_State, output: ^[dynamic]_Path) -> bool {
	if state.thread == nil || !thread.is_done(state.thread) {return false}

	for result in state.results {
		append(output, result)
	}

	thread.destroy(state.thread); state.thread = nil
	delete(state.results); state.results = nil

	return true
}
