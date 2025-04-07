#include "taglib/tag_c.h"
#include "taglib/fileref.h"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

extern "C" TagLib_File *taglib_wrapped_open(const char *utf8) {
#ifdef _WIN32
	wchar_t buf[512] = {};
	MultiByteToWideChar(CP_UTF8, 0, utf8, strlen(utf8), buf, 511);
	return reinterpret_cast<TagLib_File*>(new TagLib::FileRef(buf));
#else
	return reinterpret_cast<TagLib_File*>(new TagLib::FileRef(utf8));
#endif
}
