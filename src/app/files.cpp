/*
   Copyright 2024 Jamie Dennis

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
#include "files.h"
#include "util/auto_array_impl.h"
#include <xxhash.h>


Path_Ref Path_Pool::lookup_path(uint32 path_hash) {
	uint32 count = m_files.length();
	uint32 m = count/2;

	for (uint32 i = 0; i < m; ++i) {
		if (m_files[i].hash == path_hash) {
			return i;
		}
		if (m_files[i+m].hash == path_hash) return i+m;
	}

	if ((count % 2) && (m_files[count - 1].hash == path_hash)) return count - 1;

	return -1;
}

Path_Ref Path_Pool::add(const char *path) {
	const char *filename = get_file_name(path);
	ptrdiff_t path_length = filename - path;
	uint32 filename_length = strlen(filename);
	uint32 folder_hash = XXH32(path, path_length, 0);
	uint32 full_hash = XXH32(path, strlen(path), 0);
	uint32 folder_count = m_folders.length();
	int32 folder_index = -1;
	File file;
	Path_Ref ref;

	ref = this->lookup_path(full_hash);
	if (ref != -1) 
		return ref;

	for (uint32 i = 0; i < folder_count; ++i) {
		if (m_folders[i].hash == folder_hash) {
			folder_index = i;
			break;
		}
	}

	if (folder_index == -1) {
		Folder folder = {};
		memcpy(folder.path, path, path_length);
		folder.hash = folder_hash;
		folder_index = m_folders.append(folder);
	}
	
	file.hash = full_hash;
	file.folder = folder_index;
	file.offset = m_string_pool.push(filename_length + 1);
	for (uint32 i = 0; i < filename_length; ++i) {
		m_string_pool[file.offset + i] = filename[i];
	}
	m_string_pool[file.offset + filename_length] = 0;

	ref = m_files.append(file);
	return ref;
}

Path_Ref Path_Pool::add(const wchar_t *path) {
	char path_u8[512] = {};
	wchar_to_multibyte(path, path_u8, 512);
	return add(path_u8);
}

void Path_Pool::get(Path_Ref ref, char *buffer, uint32 buffer_max) const {
	const File& file = m_files[ref];
	snprintf(buffer, buffer_max, "%s%s", m_folders[file.folder].path, &m_string_pool[file.offset]);
}

void Path_Pool::get(Path_Ref ref, wchar_t *buffer, uint32 buffer_max) const {
	char path_u8[512];
	this->get(ref, path_u8, 512);
	multibyte_to_wchar(path_u8, buffer, buffer_max);
}

void Path_Pool::free() {
	m_files.free();
	m_string_pool.free();
	m_folders.free();
}

static Path_Pool g_path_pool;

Path_Ref store_file_path(const char *path) {
	return g_path_pool.add(path);
}

Path_Ref store_file_path(const wchar_t *path) {
	return g_path_pool.add(path);
}

void retrieve_file_path(Path_Ref ref, char *buffer, uint32 buffer_max) {
	g_path_pool.get(ref, buffer, buffer_max);
}

void retrieve_file_path(Path_Ref ref, wchar_t *buffer, uint32 buffer_max) {
	g_path_pool.get(ref, buffer, buffer_max);
}
