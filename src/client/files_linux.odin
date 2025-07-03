#+private
package client

@private
for_each_file_in_dialog :: proc(
	title: cstring, iterator: _File_Iterator, 
	iterator_data: rawptr, select_folders := false,
	multiselect := true, file_type := _File_Type.Audio
) -> int {
	//return _open_file_or_folder_multiselect_dialog(iterator, iterator_data, select_folders, multiselect, file_type)
	return 0
}

@private
open_file_dialog :: proc(buf: []u8, file_type: _File_Type) -> (file: string, ok: bool) {
	return "", false
}

