package main

string_from_array :: proc(arr: []u8) -> string {
	if arr[len(arr)-1] == 0 do return string(cstring(raw_data(arr)))
	else do return string(arr[:])
}
