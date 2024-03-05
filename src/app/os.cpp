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
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ShObjIdl.h>
#include <shellapi.h>
#include <Shlwapi.h>
#include "common.h"
#include "files.h"
#include "ui.h"
#include "util/auto_array_impl.h"


Mutex create_mutex() {
	return CreateMutex(NULL, FALSE, NULL);
}

void lock_mutex(Mutex mtx) {
	WaitForSingleObject(mtx, INFINITE);
}

void unlock_mutex(Mutex mtx) {
	ReleaseMutex(mtx);
}

void destroy_mutex(Mutex mtx) {
	CloseHandle(mtx);
}

uint64 time_get_tick() {
	LARGE_INTEGER tick;
	QueryPerformanceCounter(&tick);
	return tick.QuadPart;
}

uint64 time_get_frequency() {
	LARGE_INTEGER tick;
	QueryPerformanceFrequency(&tick);
	return tick.QuadPart;
}

uint32 wchar_to_multibyte(const wchar_t *in, char *out, uint32 out_max) {
	int ret = WideCharToMultiByte(CP_UTF8, 0, in, -1, out, out_max, NULL, NULL) - 1;
	if (ret == -1) return 0;
	return (uint32)ret;
}

uint32 multibyte_to_wchar(const char *in, wchar_t *out, uint32 out_max) {
	int ret = MultiByteToWideChar(CP_UTF8, 0, in, -1, out, out_max) - 1;
	if (ret == -1) return 0;
	return (uint32)ret;
}

static bool scan_folder(wchar_t *path_buffer, uint32 path_buffer_max, uint32 path_length, Directory_Iterator_Callback *callback, 
						uint32 depth, uint32 max_depth) {
	HANDLE find_handle;
	WIN32_FIND_DATAW find_data;
	bool ret = true;

	path_buffer[path_length] = '*';
	find_handle = FindFirstFileW(path_buffer, &find_data);
	path_buffer[path_length] = 0;

	if (find_handle == INVALID_HANDLE_VALUE) {
		log_error("Failed to open folder \"%ls\"\n", path_buffer);
		return false;
	}

	while (FindNextFileW(find_handle, &find_data)) {
		if (!wcscmp(find_data.cFileName, L"..") || !wcscmp(find_data.cFileName, L".")) continue;

		int length = swprintf(&path_buffer[path_length], path_buffer_max - path_length, L"%s", find_data.cFileName);

		if ((depth < max_depth) && (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
			path_buffer[path_length + length] = '\\';
			if (!scan_folder(path_buffer, path_buffer_max, path_length + length + 1, callback, depth + 1, max_depth)) {
				ret = false;
				goto END;
			}
			path_buffer[path_length + length] = 0;
		}
		else {
			char path_u8[512];
			wchar_to_multibyte(path_buffer, path_u8, sizeof(path_u8));

			if (!callback(path_u8)) {
				ret = false;
				goto END;
			}
		}

		memset(&path_buffer[path_length], 0, length);
	}

END:
	FindClose(find_handle);
	return ret;
}

void for_each_file_in_directory(const wchar_t *directory, Directory_Iterator_Callback *callback, uint32 max_depth) {
	wchar_t path_buffer[512] = {};
	size_t length = wcslen(directory);
	wcsncpy(path_buffer, directory, 510);
	path_buffer[length++] = '\\';
	path_buffer[length] = 0;
	scan_folder(path_buffer, 512, length, callback, 1, max_depth);
}

void for_each_file_from_dialog(Directory_Iterator_Callback *callback, File_Data_Type file_type, bool allow_multi) {
	IFileOpenDialog *dialog;
	IShellItemArray *files;
	
	COMDLG_FILTERSPEC music_types[] = {
		{L"Supported file types", L"*.wav;*.mp3;*.m4a;*.opus;*.flac;*.aiff"},
	};
	
	COMDLG_FILTERSPEC image_types[] = {
		{L"Supported image types", L"*.jpeg;*.jpg;*.png;*.tga"},
	};
	
	COMDLG_FILTERSPEC font_types[] = {
		{L"Supported font types", L"*.ttf;*.otf"},
	};
	
	(void)CoCreateInstance(CLSID_FileOpenDialog, NULL, CLSCTX_ALL, IID_IFileOpenDialog, (void **)&dialog);
	dialog->SetOptions(FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM | (FOS_ALLOWMULTISELECT*allow_multi));
	if (file_type == FILE_DATA_TYPE_IMAGE) dialog->SetFileTypes(1, image_types);
	else if (file_type == FILE_DATA_TYPE_MUSIC) dialog->SetFileTypes(1, music_types);
	else if (file_type == FILE_DATA_TYPE_FONT) dialog->SetFileTypes(1, font_types);

	if (SUCCEEDED(dialog->Show(NULL))) {
		LPWSTR path;
		DWORD count;
		dialog->GetResults(&files);
		files->GetCount(&count);

		for (DWORD i = 0; i < count; ++i) {
			IShellItem *file;
			char path_u8[512];

			files->GetItemAt(i, &file);
			file->GetDisplayName(SIGDN_FILESYSPATH, &path);
			wchar_to_multibyte(path, path_u8, 512);
			callback(path_u8);
			file->Release();
			CoTaskMemFree(path);
		}

		files->Release();
	}

	dialog->Release();
}

bool select_folder_dialog(wchar_t *buffer, uint32 buffer_max) {
	IFileOpenDialog *dialog;

	(void)CoCreateInstance(CLSID_FileOpenDialog, NULL, CLSCTX_ALL, IID_IFileOpenDialog, (void **)&dialog);
	dialog->SetOptions(FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_PICKFOLDERS);

	if (SUCCEEDED(dialog->Show(NULL))) {
		LPWSTR path;
		IShellItem *folder;

		dialog->GetResult(&folder);
		folder->GetDisplayName(SIGDN_FILESYSPATH, &path);		
		if (path) {
			wcsncpy(buffer, path, buffer_max - 1);
			buffer[buffer_max-1] = 0;
		}
		folder->Release();
		CoTaskMemFree(path);

		return true;
	}

	return false;
}

bool file_exists(const char *path) {
	wchar_t path_u16[512];
	multibyte_to_wchar(path, path_u16, 512);
	return PathFileExistsW(path_u16);
}


bool create_directory(const char *path) {
	bool result = CreateDirectoryA(path, NULL);
	USER_ASSERT_WARN(result, "Failed to create folder \"%s\". Make sure the containing folder is not read-only", path);
	return result;
}

void show_message_box(Message_Box_Type type, const char *message, ...) {
	char formatted[2048];
	va_list va;
	va_start(va, message);
	vsnprintf(formatted, sizeof(formatted), message, va);
	va_end(va);

	UINT types[MESSAGE_BOX__COUNT];
	types[MESSAGE_BOX_ERROR] = MB_ICONERROR;
	types[MESSAGE_BOX_WARNING] = MB_ICONWARNING;
	types[MESSAGE_BOX_INFO] = MB_ICONINFORMATION;

	const char *captions[MESSAGE_BOX__COUNT];
	captions[MESSAGE_BOX_ERROR] = "Error";
	captions[MESSAGE_BOX_WARNING] = "Warning";
	captions[MESSAGE_BOX_INFO] = "Information";

	MessageBoxA(NULL, formatted, captions[type], types[type]);
}
