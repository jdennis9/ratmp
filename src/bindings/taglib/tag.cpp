#include "taglib/fileref.h"
#include "taglib/tag_c.h"

extern "C" TagLib_File *taglib_file_new_wchar(const wchar_t *filename) {
	return reinterpret_cast<TagLib_File *>(new TagLib::FileRef(filename));
}
