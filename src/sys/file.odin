package sys

import "core:log"
import "core:thread"
import "core:os/os2"
import "core:path/filepath"

import "src:util"

Path :: [512]u8

File_Iterator :: #type proc(path: string, is_folder: bool, data: rawptr)
File_Type :: enum {
	Audio,
	Image,
	Font,
}

File_Dialog_State :: struct {
	thread: ^thread.Thread,
	select_folders: bool,
	multiselect: bool,
	file_type: File_Type,
	results: [dynamic]Path,
}

@(private="file")
_file_dialog_thread_proc :: proc(dialog_thread: ^thread.Thread) {
	state := cast(^File_Dialog_State) dialog_thread.data

	iterator :: proc(path: string, is_folder: bool, data: rawptr) {
		state := cast(^File_Dialog_State)data
		path_buf: Path
		util.copy_string_to_buf(path_buf[:], path)
		append(&state.results, path_buf)
	}

	for_each_file_in_dialog(nil, iterator, state, state.select_folders, state.multiselect, state.file_type)
}

open_async_file_dialog :: proc(state: ^File_Dialog_State, select_folders := true, multiselect := true, file_type := File_Type.Audio) -> bool {
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

async_file_dialog_is_running :: proc(state: File_Dialog_State) -> bool {return state.thread != nil}

// If files were selected, append them to the output array and destroy the dialog
async_file_dialog_get_results :: proc(state: ^File_Dialog_State, output: ^[dynamic]Path) -> bool {
	if state.thread == nil || !thread.is_done(state.thread) {return false}

	defer {thread.destroy(state.thread); state.thread = nil}
	defer {delete(state.results); state.results = nil}

	if len(state.results) == 0 {
		return false
	}

	for result in state.results {
		append(output, result)
	}

	return true
}
