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
package main

import "core:path/filepath"
import "core:log"
import "core:thread"

Path :: [512]u8

File_Proc :: #type proc(path: string, is_folder: bool, data: rawptr)

File_Type :: enum {
	Audio,
	Image,
}

File_Dialog_Flag :: enum {
	SelectFolders,
	SelectMultiple,
}
File_Dialog_Flags :: bit_set[File_Dialog_Flag]

File_Dialog_State :: struct {
	thread:    ^thread.Thread,
	flags:     File_Dialog_Flags,
	file_type: File_Type,
	results:   [dynamic]Path,
}

FILE_TYPE_EXTENSIONS := [File_Type][]string {
	.Audio = {
		".mp3", ".aac", ".m4a", ".wav",
		".alac", ".flac", ".ape", ".ogg",
		".opus",
	},
	.Image = {
		".jpg", ".jpeg", ".png", ".webp", ".tiff",
		".tga", ".bmp",
	},
}

@(private="file")
_file_dialog_thread_proc :: proc(dialog_thread: ^thread.Thread) {
	state := cast(^File_Dialog_State) dialog_thread.data

	iterator :: proc(path: string, is_folder: bool, data: rawptr) {
		state := cast(^File_Dialog_State)data
		path_buf: Path
		copy(path_buf[:len(path_buf)-1], path)
		append(&state.results, path_buf)
	}

	for_each_file_in_dialog(nil, iterator, state, state.file_type, state.flags)
}

file_is_type :: proc(path: string, type: File_Type) -> bool {
	ext := filepath.ext(path)
	if ext == "" do return false
	for e in FILE_TYPE_EXTENSIONS[type] {
		if ext == e do return true
	}

	return false
}

guess_file_mime_type :: proc(path: string) -> string {
	ext := filepath.ext(path)

	switch ext {
	case ".jpg", ".jpeg": return "image/jpeg"
	case ".png": return "image/png"
	case ".webp": return "image/webp"
	case ".tiff": return "image/tiff"
	case ".tga": return "image/tga"
	case ".bmp": return "image/bmp"
	}

	return ""
}

async_file_dialog_open :: proc(state: ^File_Dialog_State, file_type: File_Type, flags: File_Dialog_Flags) -> bool {
	if state.thread != nil {
		log.warn("Tried openning a file dialog in the background when there is already one running")
		return false
	}

	state.flags = flags
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
