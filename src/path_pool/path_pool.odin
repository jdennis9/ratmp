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
package path_pool

import "base:runtime"
import "core:path/filepath"
import "core:hash/xxhash"
import "core:strings"

@private
_Offset_Length :: struct {offset, length: int}

Dir :: struct {
	id: u32,
	name_length: int,
	stored_paths: map[u32]_Offset_Length,
	string_pool: [dynamic]u8,
}

Path :: struct {
	dir, offset, length: int,
}

Pool :: struct {
	allocator: runtime.Allocator,
	dirs: [dynamic]Dir,
}

@private
_append_string :: proc(pool: ^[dynamic]u8, str: string) -> (offset, length: int) {
	length = len(str)
	offset = len(pool)
	for i in 0..<length {
		append(pool, str[i])
	}
	return
}

init :: proc(pool: ^Pool, allocator := context.allocator) {
	pool.allocator = allocator
	pool.dirs = make([dynamic]Dir, allocator)
}

@private
_hash_id :: proc(str: string) -> u32 {
	return xxhash.XXH32(transmute([]u8) str)
}

@private
_get_dir :: proc(pool: Pool, id: u32) -> (int, bool) {
	for dir, index in pool.dirs {
		if dir.id == id {return index, true}
	}

	return 0, false
}

@private
_add_to_dir :: proc(dir: ^Dir, dir_index: int, filename: string, path_id: u32) -> Path {
	offset, length := _append_string(&dir.string_pool, filename)
	dir.stored_paths[path_id] = _Offset_Length{offset, length}
	return Path {
		dir = dir_index,
		offset = offset,
		length = length,
	}
}

store :: proc(pool: ^Pool, path: string) -> (loc: Path) {
	dir_name := filepath.dir(path)
	defer delete(dir_name)
	file_name := filepath.base(path)

	dir_id := _hash_id(dir_name)
	path_id := _hash_id(path)

	if dir_index, found_dir := _get_dir(pool^, dir_id); found_dir {
		dir := &pool.dirs[dir_index]
		if existing, exists := dir.stored_paths[path_id]; exists {
			loc.dir = dir_index
			loc.offset = existing.offset
			loc.length = existing.length

			return
		}

		loc = _add_to_dir(dir, dir_index, file_name, path_id)
		return
	}

	dir := Dir {
		id = dir_id,
		name_length = len(dir_name),
		stored_paths = make(map[u32]_Offset_Length, pool.allocator),
		string_pool = make([dynamic]u8, pool.allocator),
	}

	dir_index := len(pool.dirs)

	_append_string(&dir.string_pool, dir_name)
	loc = _add_to_dir(&dir, dir_index, file_name, path_id)
	append(&pool.dirs, dir)

	return
}

get_dir_path :: proc(dir: Dir) -> string {
	return string(dir.string_pool[:dir.name_length])
}

// Returns a slice of the buffer or nil if the buffer is too small
retrieve :: proc(pool: Pool, path: Path, buffer: []u8) -> string {
	dir := pool.dirs[path.dir]
	total_length := dir.name_length + path.length + 1

	if total_length >= len(buffer) {
		return ""
	}

	copy(buffer, dir.string_pool[:dir.name_length])
	buffer[dir.name_length] = filepath.SEPARATOR
	copy(buffer[dir.name_length+1:], dir.string_pool[path.offset:][:path.length])

	return string(buffer[:total_length])
}

retrieve_cstring :: proc(pool: Pool, path: Path, buffer: []u8) -> cstring {
	assert(len(buffer) >= 16)
	str := retrieve(pool, path, buffer[:len(buffer)-2])
	if str == "" {return nil}
	buffer[len(str)] = 0
	return strings.unsafe_string_to_cstring(str)
}

destroy :: proc(pool: Pool) {
	for dir in pool.dirs {
		delete(dir.string_pool)
		delete(dir.stored_paths)
	}
	delete(pool.dirs)
}
