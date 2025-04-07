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
package path_pool;

import "core:path/filepath";
import "core:hash/xxhash";
import "core:strings";

Dir :: struct {
	id: u32,
	length: int,
	string_pool: [dynamic]u8,
};

Path :: struct {
	dir, offset, length: int,
};

Pool :: struct {
	dirs: [dynamic]Dir,
};

@private
_append_string :: proc(pool: ^[dynamic]u8, str: string) -> (offset, length: int) {
	length = len(str);
	offset = len(pool);
	for i in 0..<length {
		append(pool, str[i]);
	}
	return;
}

store :: proc(pool: ^Pool, path: string) -> (ret: Path) {
	dir_name := filepath.dir(path);
	defer delete(dir_name);
	file_name := filepath.base(path);

	dir_id := xxhash.XXH32(transmute([]u8) dir_name);

	for &dir, dir_index in pool.dirs {
		if dir_id == dir.id {
			ret.dir = dir_index;
			ret.offset, ret.length = _append_string(&dir.string_pool, file_name);
			return;
		}
	}

	// Directory not found, add it to the pool
	dir := Dir {
		id = dir_id,
		length = auto_cast len(dir_name),
	};

	// Append directory name to the start of the string pool
	_append_string(&dir.string_pool, dir_name);
	
	// Append file name without directory
	ret.dir = len(pool.dirs);
	ret.offset, ret.length = _append_string(&dir.string_pool, file_name);

	// Add the new directory to the pool
	append(&pool.dirs, dir);

	return;
}

// Returns a slice of the buffer or nil if the buffer is too small
retrieve :: proc(pool: ^Pool, path: Path, buffer: []u8) -> string {
	dir := pool.dirs[path.dir];
	total_length := dir.length + path.length + 1;

	if total_length >= len(buffer) {
		return "";
	}

	copy(buffer, dir.string_pool[:dir.length]);
	buffer[dir.length] = filepath.SEPARATOR;
	copy(buffer[dir.length+1:], dir.string_pool[path.offset:][:path.length]);

	return string(buffer[:total_length]);
}

retrieve_cstring :: proc(pool: ^Pool, path: Path, buffer: []u8) -> cstring {
	assert(len(buffer) >= 16);
	str := retrieve(pool, path, buffer[:len(buffer)-2]);
	if str == "" {return nil;}
	buffer[len(str)] = 0;
	return strings.unsafe_string_to_cstring(str);
}

destroy :: proc(pool: ^Pool) {
	for dir in pool.dirs {
		delete(dir.string_pool);
	}
	delete(pool.dirs);
}
