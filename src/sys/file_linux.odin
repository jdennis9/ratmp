#+private
package sys

for_each_file_in_dialog :: proc(
	title: cstring, iterator: File_Iterator, 
	iterator_data: rawptr, select_folders := false,
	multiselect := true, file_type := _File_Type.Audio
) -> int {
	return 0
}

open_file_dialog :: proc(buf: []u8, file_type: File_Type) -> (file: string, ok: bool) {
	return "", false
}

