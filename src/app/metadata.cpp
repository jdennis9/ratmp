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
#include "metadata.h"
#include "files.h"
#include "util/auto_array_impl.h"
#include "util/hash_map_impl.h"
extern "C" {
#include <libavformat/avformat.h>
#include <ctype.h>
}

#define METADATA_CACHE_PATH ".\\cache\\metadata"


static const char *EMPTY_STRING = "<error>";

struct Metadata {
	uint32 offsets[METADATA__COUNT];
};

static struct {
	Hash_Map<Metadata> metadata;
	Auto_Array<char> string_pool;
	bool initialized;
} G;

static uint32 push_string(const char *str) {
	size_t length = strlen(str);
	uint32 offset = G.string_pool.push(length + 1);
	for (uint32 i = 0; i < length; ++i) {
		G.string_pool[offset + i] = str[i];
	}
	G.string_pool[offset + length] = 0;
	return offset;
}


static void init_cache() {
	// A metadata offset of 0 should mean no data.
	// For ImGui an empty string will cause errors so we
	// place a space at an offset of 0 in the cache.
	push_string(" ");
	G.initialized = true;
}

Metadata_Ref retrieve_metadata(const char *pathname) {
	Metadata_Ref ref = 0;
	Metadata metadata = {};
	AVFormatContext *input = NULL;
	AVDictionaryEntry *entry;

	if (!G.initialized) init_cache();

	ref = G.metadata.lookup(pathname);
	if (ref >= 0) {
		return ref;
	}

	avformat_open_input(&input, pathname, NULL, NULL);
	if (input == NULL) 
		return INVALID_METADATA_REF;
	avformat_find_stream_info(input, NULL);

	
	// Map libavformat metadata dictionary entry names to
	// Metadata_Type names
	const struct {
		Metadata_Type type;
		const char *name;
	} mappings[] = {
		{METADATA_TITLE, "title"},
		{METADATA_ARTIST, "artist"},
		{METADATA_ALBUM, "album"},
	};
	
	// Check metadata dictionary entries for mapped metadata types
	for (uint32 i = 0; i < ARRAY_LENGTH(mappings); ++i) {
		if (entry = av_dict_get(input->metadata, mappings[i].name, NULL, 0)) {
			metadata.offsets[mappings[i].type] = push_string(entry->value);
		}
		else if (mappings[i].type == METADATA_TITLE) {
			metadata.offsets[METADATA_TITLE] = push_string(get_file_name(pathname));
		}
	}
	
	// Get duration (may end up with 0)
	{
		int64 duration = input->duration / AV_TIME_BASE;
		char duration_string[64];
		format_time(duration, duration_string, 64);
		metadata.offsets[METADATA_DURATION] = push_string(duration_string);
	}
	
	avformat_close_input(&input);
	avformat_free_context(input);
	
	return G.metadata.add(pathname, metadata);
}

const char *get_metadata_string(Metadata_Ref ref, Metadata_Type type) {
	if (ref == INVALID_METADATA_REF) return EMPTY_STRING;
	Metadata m = G.metadata[ref].value;
	return &G.string_pool[m.offsets[type]];
}

bool metadata_string_is_empty(const char *str) {
	return !strcmp(str, EMPTY_STRING);
}

void save_metadata_cache() {
	GET_METADATA_TYPE_NAMES(string_names);
	const char *string;
	FILE *file = fopen(METADATA_CACHE_PATH, "w");
	uint32 track_count = G.metadata.length();

	USER_ASSERT_WARN(file != nullptr, "Failed to write metadata cache. Launch times may be very slow.");
	if (!file) return;

	for (uint32 track_index = 0; track_index < track_count; ++track_index) {
		Metadata *strings = &G.metadata[track_index].value;
		fprintf(file, "%x", G.metadata[track_index].key);
		for (uint32 i = 0; i < METADATA__COUNT; ++i) {
			if (strings->offsets[i]) {
				string = &G.string_pool[strings->offsets[i]];
				fprintf(file, " %s %zu %s", string_names[i], strlen(string), string);
			}
		}
		fprintf(file, "\n");
	}

	fclose(file);
}

static inline char *eat_spaces(char *c) {
	for (; *c && isspace(*c); ++c);
	return c;
}

void load_metadata_cache() {
	G.metadata.reset();
	G.string_pool.reset();
	push_string(" ");
	
	char *buffer;
	const char *reader;
	long buffer_size;
	char line[2048];
	FILE *file = fopen(METADATA_CACHE_PATH, "r");
	if (!file) {
		if (!file_exists("cache")) create_directory("cache");
		return;
	}
	
	fseek(file, 0, SEEK_END);
	buffer_size = ftell(file);
	buffer = (char*)malloc(buffer_size+1);
	fseek(file, 0, SEEK_SET);
	fread(buffer, buffer_size, 1, file);
	fclose(file);
	buffer[buffer_size] = 0;
	
	GET_METADATA_TYPE_NAMES(type_names);

	reader = buffer;
	
	while (reader = read_line(reader, line, sizeof(line))) {
		char *string = line;
		uint32 id = (uint32)strtoll(string, &string, 16);
		Metadata data = {};

		while (1) {
			const char *delim = " \t";
			Metadata_Type type = METADATA__COUNT;
			uint32 length;
			char buffer[256] = {};

			// Read tag type
			string = eat_spaces(string);
			if (!string) break;
			string = strtok(string, delim);
			if (!string) break;
			
			for (uint32 i = 0; i < METADATA__COUNT; ++i) {
				if (!strcmp(string, type_names[i])) {
					type = (Metadata_Type)i;
					break;
				}
			}
			
			if (type == METADATA__COUNT) break;

			// Read string data
			string += strlen(string) + 1;
			string = eat_spaces(string);
			if (!string) break;
			string = strtok(string, delim);
			if (!string) break;

			length = strtol(string, NULL, 10);
			string += strlen(string) + 1;
			strncpy(buffer, string, length);
			string += length + 1;

			data.offsets[type] = push_string(buffer);
		}

		G.metadata.add(id, data);
	}

	free(buffer);
}
