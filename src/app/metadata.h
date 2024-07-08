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
#ifndef METADATA_H
#define METADATA_H

#include "common.h"

enum Metadata_Type {
	METADATA_TITLE,
	METADATA_ARTIST,
	METADATA_ALBUM,
	METADATA_DURATION,
	METADATA__COUNT,
};

#define GET_METADATA_TYPE_NAMES(name) \
const char *name[METADATA__COUNT] = {};\
name[METADATA_TITLE] = "TITLE";\
name[METADATA_ARTIST] = "ARTIST";\
name[METADATA_ALBUM] = "ALBUM";\
name[METADATA_DURATION] = "DURATION";\

typedef int32 Metadata_Ref;
#define INVALID_METADATA_REF -1

Metadata_Ref retrieve_metadata(const char *file);
const char *get_metadata_string(Metadata_Ref ref, Metadata_Type type);
bool metadata_string_is_empty(const char *str);
void save_metadata_cache();
void load_metadata_cache();

#endif
