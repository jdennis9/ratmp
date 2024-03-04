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
#include "tracklist.h"
#include "stream.h"
#include "metadata.h"
#include "ui.h"
#include "util/auto_array_impl.h"
#include <stdlib.h>
#include <io.h>

bool Tracklist::add(Track track) {
	uint32 track_count = m_tracks.length();
	for (uint32 i = 0; i < track_count; ++i) {
		if (m_tracks[i].metadata == track.metadata) 
			return true;
	}
	m_tracks.append(track);
	ui_add_to_library(track);
	return true;
}

bool Tracklist::add(const char *path) {
	Track track;
	if (!stream_file_is_supported(path) || !file_exists(path)) 
		return false;

	track.path = store_file_path(path);
	track.metadata = retrieve_metadata(path);
	add(track);

	return true;
}

int32 Tracklist::index_of_track(const Track &track) {
	uint32 track_count = m_tracks.length();
	for (uint32 i = 0; i < track_count; ++i) {
		if (m_tracks[i].metadata == track.metadata) return i;
	}
	return -1;
}

uint32 Tracklist::length() const {
	return m_tracks.length();
}

void Tracklist::copy(Tracklist *list) const {
	uint32 track_count = m_tracks.length();

	for (uint32 i = 0; i < track_count; ++i) {
		list->add(m_tracks[i]);
	}
}

void Tracklist::copy_selection(Tracklist *dst) const {
	uint32 track_count = (m_selection.last - m_selection.first) + 1;
	if (track_count > m_tracks.length()) return;
	uint32 tracks_copied = 0;

	for (int32 i = m_selection.first; i <= m_selection.last; ++i) {
		dst->add(m_tracks[i]);
	}
}

void Tracklist::copy_with_filter(Tracklist *dst, const Track_Filter *filter) const {
	uint32 track_count = m_tracks.length();

	for (uint32 i = 0; i < track_count; ++i) {
		const char *album = get_metadata_string(m_tracks[i].metadata, METADATA_ALBUM);
		const char *artist = get_metadata_string(m_tracks[i].metadata, METADATA_ARTIST);
		const char *title = get_metadata_string(m_tracks[i].metadata, METADATA_TITLE);

		if (filter->check(album, artist, title)) dst->add(m_tracks[i]);
	}
}

void Tracklist::remove_selection() {
	m_tracks.remove_range(m_selection.first, m_selection.last);
}

void Tracklist::select(int32 index) {
	m_selection.first = index;
	m_selection.last = index;
}

void Tracklist::select_to(int32 index) {
	m_selection.last = index;
	if (m_selection.first > m_selection.last) {
		auto t = m_selection.first;
		m_selection.first = m_selection.last;
		m_selection.last = t;
	}
}

void Tracklist::shuffle() {
	uint32 track_count = m_tracks.length();

	for (uint32 i = 0; i < track_count; ++i) {
		Track t = m_tracks[i];
		uint32 j = rand() % track_count;
		m_tracks[i] = m_tracks[j];
		m_tracks[j] = t;
	}
}

void Tracklist::clear() {
	m_tracks.reset();
}

const char *Tracklist::get_filename() const {
	return m_filename;
}

uint32 Tracklist::load_from_file(const char *path) {
	char line[1024];
	FILE *file;
	uint32 count = 0;
	size_t length = 0;

	//strncpy(m_filename, get_file_name(path), sizeof(m_filename)-1);
	strncpy(m_filename, path, sizeof(m_filename)-1);

	file = fopen(path, "r");

	if (!file) return 0;
	if (fgets(line, 1024, file)) {} // Version

	// Name
	if (fgets(line, 1024, file)) {
		length = strlen(line);
		line[length - 1] = 0;
		strncpy(this->name, line, sizeof(this->name)-1);
	}

	while (fgets(line, 1024, file)) {
		length = strlen(line);
		line[length - 1] = 0;
		count += this->add(line);
	}

	fclose(file);
	return count;
}

void Tracklist::save_to_file(const char *path) {
	char filename[16];
	
	if (!path && !m_filename[0]) {
		strcpy(filename, "XXXXXX");
		if (!_mktemp(filename)) {
			return;
		}
		snprintf(m_filename, sizeof(m_filename), ".\\playlists\\%s", filename);
	}
	else if (path) {
		strncpy(m_filename, path, sizeof(m_filename)-1);
	}

	FILE *file;

	file = fopen(m_filename, "w");
	if (!file) return;

	fprintf(file, "1\n");
	fprintf(file, "%s\n", this->name);

	uint32 track_count = m_tracks.length();
	for (uint32 i = 0; i < track_count; ++i) {
		char track_path[512];
		retrieve_file_path(m_tracks[i].path, track_path, 512);
		fprintf(file, "%s\n", track_path);
	}

	fclose(file);
}

void Tracklist::delete_file() {
	if (!m_filename[0]) return;
	remove(m_filename);
}
