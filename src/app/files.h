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
#ifndef FILES_H
#define FILES_H

#include "common.h"
#include "util/auto_array.h"
#include <string.h>
#include <stdlib.h>

static inline const char *get_file_extension(const char *path) {
	int64 length = strlen(path);
	for (int64 i = length - 1; i >= 0; i--) {
		if (path[i] == '.') {
			return &path[i + 1];
		}
	}
	
	return path;
}

static const char *get_file_name(const char *path) {
	int64 length = strlen(path);

	for (int64 i = length - 1; i >= 0; --i) {
		if (path[i] == '\\') return &path[i + 1];
	}

	return path;
}

static uint32 get_file_name_length_without_extension(const char *path) {
	const char *filename = get_file_name(path);
	const char *extension = get_file_extension(path);
	
	if (extension == path || extension < filename) return (uint32)strlen(filename);
	else return (uint32)(extension - filename - 1);
}


static inline const char *read_line(const char *in, char *out, int out_size) {
	int out_count = 0;
	if (!*in) return NULL;
	
	while (*in && *in == '\n') in++;
	
	for (; *in && (*in != '\n') && (out_count < (out_size-1)); ++in, ++out_count) {
		out[out_count] = *in;
	}
	out[out_count] = 0;
	if (!out_count) return NULL;
	return *in ? in + 1 : in;
}

static inline uint32 read_whole_file_string(const char *path, char **data) {
	FILE *f = fopen(path, "rb");
	long size;
	if (!f) return 0;
	
	fseek(f, 0, SEEK_END);
	size = ftell(f);
	fseek(f, 0, SEEK_SET);
	*data = (char*)malloc(size+1);
	fread(*data, size, 1, f);
	(*data)[size] = 0;
	
	fclose(f);
	return (uint32)size;
}

// Used to reduce memory usage from storing large amounts of paths. 
// Use the global store_file_path and retrieve_file_path API for long-term path storage.

typedef int32 Path_Ref;

struct Path_Pool {
	struct Folder {
		uint32 hash;
		char path[508];
	};

	struct File {
		uint32 hash;
		uint32 folder;
		uint32 offset;
	};
	
	Auto_Array<Folder> m_folders;
	Auto_Array<File> m_files;
	Auto_Array<char> m_string_pool;
	uint32 m_folder_count;
	
	Path_Ref lookup_path(uint32 hash);
	Path_Ref add(const char *path);
	Path_Ref add(const wchar_t *path);
	void get(Path_Ref path, char *buffer, uint32 buffer_max) const;
	void get(Path_Ref path, wchar_t *buffer, uint32 buffer_max) const;
	void free();
};

Path_Ref store_file_path(const char *path);
Path_Ref store_file_path(const wchar_t *path);
void retrieve_file_path(Path_Ref ref, char *buffer, uint32 buffer_size);
void retrieve_file_path(Path_Ref ref, wchar_t *buffer, uint32 buffer_size);

enum File_Data_Type {
	FILE_DATA_TYPE_MUSIC,
	FILE_DATA_TYPE_IMAGE,
	FILE_DATA_TYPE_FONT,
};

typedef bool Directory_Iterator_Callback(const char *path);

// Recursively walk through directory and subdirectories, calling callback for each file.
void for_each_file_in_directory(const wchar_t *directory, Directory_Iterator_Callback *callback, uint32 max_depth = UINT32_MAX);
// Open multiselect file dialog
void for_each_file_from_dialog(Directory_Iterator_Callback *callback, File_Data_Type type, bool allow_multi = true);
// Open dialog to select single folder and write the path to buffer
bool select_folder_dialog(wchar_t *buffer, uint32 buffer_max);
bool file_exists(const char *path);
bool create_directory(const char *path);

#endif //FILES_H
