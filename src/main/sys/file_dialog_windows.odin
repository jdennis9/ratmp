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

import "src:main/shared"
import "core:testing"
import "core:strings"
import "core:mem"
import win "core:sys/windows"

win32_check :: shared.win32_check

@require_results
show_file_dialog :: proc(
	params: File_Dialog_Params, results_allocator: mem.Allocator
) -> (results: []string, ok: bool) {
	scratch: mem.Scratch
	
	mem.scratch_init(&scratch, 64<<10)
	defer mem.scratch_destroy(&scratch)
	
	temp_allocator := mem.scratch_allocator(&scratch)

	dialog: ^win.IFileOpenDialog
	options: win.FILEOPENDIALOGOPTIONS = win.FOS_FILEMUSTEXIST|win.FOS_PATHMUSTEXIST

	win32_check(win.CoCreateInstance(
		win.CLSID_FileOpenDialog, nil, win.CLSCTX_INPROC_SERVER,
		win.IID_IFileOpenDialog, cast(^rawptr) &dialog
	)) or_return

	if params.select_folders do options |= win.FOS_PICKFOLDERS
	if params.select_multiple do options |= win.FOS_ALLOWMULTISELECT

	dialog->SetOptions(options)

	if params.file_types != nil {
		assert(len(params.file_types) <= FILE_DIALOG_MAX_FILE_TYPES)

		filter: [dynamic; FILE_DIALOG_MAX_FILE_TYPES]win.COMDLG_FILTERSPEC

		for ft in params.file_types {
			sb: strings.Builder

			name := win.utf8_to_wstring_alloc(ft.name, temp_allocator)

			for ext, i in ft.extensions {
				strings.write_string(&sb, "*")
				strings.write_string(&sb, ext)
				if i != len(ft.extensions) - 1 {
					strings.write_string(&sb, ";")
				}
			}

			extensions := win.utf8_to_wstring_alloc(strings.to_string(sb), temp_allocator)

			append(&filter, win.COMDLG_FILTERSPEC {
				pszName = name,
				pszSpec = extensions,
			})
		}

		dialog->SetFileTypes(auto_cast len(filter), &filter[0])
	}

	win32_check(dialog->Show(nil))

	if params.select_multiple {
		items: ^win.IShellItemArray
		win32_check(dialog->GetResults(&items)) or_return
		defer items->Release()

		results_count: win.DWORD
		win32_check(items->GetCount(&results_count)) or_return

		results = make([]string, results_count, results_allocator)

		for i in 0..<results_count {
			path: [^]u16
			item: ^win.IShellItem

			win32_check(items->GetItemAt(i, &item)) or_continue
			defer item->Release()

			win32_check(item->GetDisplayName(.FILESYSPATH, auto_cast &path)) or_continue
			defer win.CoTaskMemFree(path)

			results[i] = win.utf16_to_utf8_alloc(
				path[:len(cstring16(path))], results_allocator
			) or_continue
		}
	}
	else {
		item: ^win.IShellItem
		path: [^]u16

		win32_check(dialog->GetResult(&item)) or_return
		defer item->Release()

		win32_check(item->GetDisplayName(.FILESYSPATH, auto_cast &path)) or_return
		defer win.CoTaskMemFree(path)

		results[0], _ = win.utf16_to_utf8_alloc(
			path[:len(cstring16(path))], results_allocator
		)
	}

	ok = true
	return
}

@test
test_win32_file_dialog :: proc(t: ^testing.T) {
	win.CoInitializeEx()
	defer win.CoUninitialize()

	results, picked := show_file_dialog({
		select_multiple = true,
		title = "Choose some files!",
		file_types = []File_Dialog_File_Type {
			File_Dialog_File_Type {
				extensions = {".mp3", ".flac", ".wav"},
				name = "Supported Audio File"
			}
		},
	}, context.allocator)
}
