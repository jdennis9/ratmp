package main

import "base:runtime"
import "core:os"
import "core:fmt"
import "core:log"
import "core:time"
import "core:hash/xxhash"

string_from_array :: proc(arr: []u8) -> string {
	if arr[len(arr)-1] == 0 do return string(cstring(raw_data(arr)))
	else do return string(arr[:])
}

set_cstring_buf :: proc(buf: []u8, str: string) {
	copy(buf[:len(buf)-1], str)
}

hash_string_64 :: proc(str: string) -> u64 {
	return xxhash.XXH3_64_default(transmute([]u8) str)
}

hash_string_32 :: proc(str: string) -> u32 {
	return xxhash.XXH32(transmute([]u8) str)
}

format_duration :: proc(buf: []u8, seconds: int) {
	h, m, s := time.clock_from_seconds(auto_cast seconds)
	fmt.bprintf(buf, "%02d:%02d:%02d", h, m ,s)
}

@(deferred_out=_TIMED_SCOPE_EXIT)
TIME_SCOPE :: proc(
	name_args: ..any, sep := " ", loc := #caller_location
) -> (string, time.Tick, runtime.Source_Code_Location) {
	name := fmt.aprint(..name_args, sep=sep, allocator=context.allocator)
	start := time.tick_now()
	return name, start, loc
}

@(private="file")
_TIMED_SCOPE_EXIT :: proc(name: string, start: time.Tick, loc: runtime.Source_Code_Location) {
	duration := time.tick_since(start)
	log.debugf("[TIMER] %s: %gms", name, time.duration_milliseconds(duration), location = loc)
	delete(name)
}

ensure_dir :: proc(path: string) {
	if os.exists(path) do return
	os.make_directory_all(path)
}
