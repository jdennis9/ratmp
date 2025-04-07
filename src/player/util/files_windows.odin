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
package util;

import win "core:sys/windows";
import "core:strings";
import "core:log";
import "core:os";
import "core:unicode/utf16";

@(private="file")
wstring_length :: proc(str: [^]u16) -> int {
	i: int;
	for {
		if str[i] == 0 {return i;}
		i += 1;
	}
}

@(private="file")
_open_file_or_folder_select_dialog :: proc(buffer: []u16, select_folders: bool) -> bool {
	dialog: ^win.IFileDialog;
	error := win.CoCreateInstance(win.CLSID_FileOpenDialog, nil, 
		win.CLSCTX_INPROC_SERVER, win.IID_IFileDialog, cast(^rawptr) &dialog);
	
	if error != 0 {
		return false;
	}

	defer dialog->Release();

	if select_folders {
		dialog->SetOptions(win.FOS_PICKFOLDERS | win.FOS_PATHMUSTEXIST);
	}
	else {
		dialog->SetOptions(win.FOS_FILEMUSTEXIST);
	}

	error = dialog->Show(nil);
	if error != 0 {
		return false;
	}

	selected_item: ^win.IShellItem;
	error = dialog->GetResult(&selected_item);
	if error != 0 {
		return false;
	}
	defer selected_item->Release();

	selected_item_path: win.LPWSTR;
	selected_item->GetDisplayName(.FILESYSPATH, &selected_item_path);

	if selected_item_path == nil {
		return false;
	}

	defer win.CoTaskMemFree(selected_item_path);

	return true;
}

@(private="file")
_open_file_or_folder_multiselect_dialog :: proc(iterator: File_Iterator, iterator_data: rawptr, select_folders: bool) -> int {
	dialog: ^win.IFileOpenDialog;
	error := win.CoCreateInstance(
		win.CLSID_FileOpenDialog, nil,
		win.CLSCTX_INPROC_SERVER, win.IID_IFileOpenDialog,
		cast(^rawptr) &dialog);
	
	if error != 0 {return 0;}

	defer dialog->Release();

	if select_folders {
		dialog->SetOptions(win.FOS_PICKFOLDERS | win.FOS_PATHMUSTEXIST | win.FOS_ALLOWMULTISELECT);
	}
	else {
		dialog->SetOptions(win.FOS_FILEMUSTEXIST | win.FOS_ALLOWMULTISELECT);
	}

	error = dialog->Show(nil);
	if error != 0 {return 0;}

	items: ^win.IShellItemArray;
	error = dialog->GetResults(&items);
	if error != 0 {return 0;}
	defer items->Release();

	count: win.DWORD;
	items->GetCount(&count);

	for i in 0..<count {
		path: win.LPWSTR;
		item: ^win.IShellItem;
		path_u8: [384]u8;
		path_len: int;

		items->GetItemAt(i, &item);
		if item == nil {continue}
		defer item->Release();
		item->GetDisplayName(.FILESYSPATH, &path);
		if path == nil {continue}
		defer win.CoTaskMemFree(path);

		path_len = cast(int) win.WideCharToMultiByte(win.CP_UTF8, 0, path, -1, &path_u8[0], len(path_u8)-1, nil, nil);

		if path_len == 0 {continue}

		iterator(transmute(string) path_u8[:path_len-1], select_folders, iterator_data);
	}

	return int(count);
}

for_each_file_in_dialog :: proc(title: cstring, iterator: File_Iterator, 
	iterator_data: rawptr, select_folders := false) -> int {
	return _open_file_or_folder_multiselect_dialog(iterator, iterator_data, select_folders);
}

open_file_dialog :: proc(buf: []u8) -> (file: string, ok: bool) {
	dialog: ^win.IFileDialog;
	hr := win.CoCreateInstance(win.CLSID_FileOpenDialog, nil, win.CLSCTX_INPROC_SERVER,
		win.IID_IFileOpenDialog, cast(^rawptr) &dialog);
	if !win.SUCCEEDED(hr) {return}
	
	defer dialog->Release();
	dialog->SetOptions(win.FOS_FILEMUSTEXIST);

	hr = dialog->Show(nil);
	if !win.SUCCEEDED(hr) {return}

	result: ^win.IShellItem;
	hr = dialog->GetResult(&result);
	if !win.SUCCEEDED(hr) {return}
	defer result->Release();

	result_path: win.LPWSTR;
	result->GetDisplayName(.FILESYSPATH, &result_path);
	if result_path == nil {return}
	defer win.CoTaskMemFree(result_path);

	path_len := win.WideCharToMultiByte(win.CP_UTF8, 0, result_path, -1, &buf[0], auto_cast len(buf)-1, nil, nil);
	if path_len == 0 {return}

	return string(buf[:path_len-1]), true;
}
