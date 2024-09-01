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
#include "embedded/missing_thumbnail.h"
#include <stb_image.h>
#include <stdlib.h>
#include <io.h>
#include <xxhash.h>

// One global album list is stored and added to when add() is called on a tracklist
struct Album_List {
	Auto_Array<uint64> ids; // XXH3_64bits hash of the album name
	Auto_Array<Album> albums;
};

static Album_List g_albums;

const Auto_Array<Album> &get_albums() {
	return g_albums.albums;
}

struct Async_Load_Thumbnail {
	char path[512];
	uint32 album;
};

struct Thumbnail_Query {
	Path_Ref path;
	uint32 album_index;
};

struct Thumbnail_Result {
	uint32 album_index;
	Image image;
};

static int thumbnail_load_thread(void *dont_care);

struct Thumbnail_Queue {
	Auto_Array<Thumbnail_Query> queue;
	Auto_Array<Thumbnail_Result> results;
	Event event;
	Mutex lock;
	Mutex results_lock;
	
	Thumbnail_Queue() {
		event = create_event();
		lock = create_mutex();
		results_lock = create_mutex();
		create_thread(&thumbnail_load_thread, NULL);
	}
};

static Thumbnail_Queue g_thumbnail_queue;

static int thumbnail_load_thread(void *dont_care) {
	Thumbnail_Queue& queue = g_thumbnail_queue;
	Auto_Array<Thumbnail_Query> queries = {};
	
	while (1) {
		event_wait(queue.event);
		lock_mutex(queue.lock);
		queries.reset();
		queue.queue.copy_to(queries);
		unlock_mutex(queue.lock);
		
		char path[512];
		for (uint32 i = 0; i < queries.m_count; ++i) {
			Thumbnail_Query& query = queries[i];
			retrieve_file_path(query.path, path, sizeof(path));
			Thumbnail_Result result = {};
			result.album_index = query.album_index;
			if (stream_extract_thumbnail(path, 128, &result.image)) {
				lock_mutex(queue.results_lock);
				queue.results.append(result);
				unlock_mutex(queue.results_lock);
			} else {
				result.image.data = NULL;
				lock_mutex(queue.results_lock);
				queue.results.append(result);
				unlock_mutex(queue.results_lock);
			}
		}
	}
	
	return 0;
}

static void queue_thumbnail_load(uint32 album, Path_Ref path) {
	Thumbnail_Query query;
	query.album_index = album;
	query.path = path;
	lock_mutex(g_thumbnail_queue.lock);
	g_thumbnail_queue.queue.append(query);
	unlock_mutex(g_thumbnail_queue.lock);
	event_signal(g_thumbnail_queue.event);
}

void check_album_thumbnail_queue() {
	//START_TIMER(timer, "Create album thumbnail textures");
	lock_mutex(g_thumbnail_queue.results_lock);
	Auto_Array<Thumbnail_Result>& results = g_thumbnail_queue.results;
	for (uint32 i = 0; i < results.m_count; ++i) {
		uint32 index = results[i].album_index;
		if (results[i].image.data) {
			g_albums.albums[index].thumbnail = create_texture_from_image(&results[i].image);
		}
		else {
			static Texture *missing_thumbnail;
			if (!missing_thumbnail) {
				Image image;
				image.data = stbi_load_from_memory(MISSING_THUMBNAIL_DATA, 
												   MISSING_THUMBNAIL_SIZE, 
												   &image.width, &image.height, 
												   NULL, 4);
				missing_thumbnail = create_texture_from_image(&image);
				stbi_image_free(image.data);
			}
			g_albums.albums[index].thumbnail = missing_thumbnail;
		}
	}
	results.reset();
	unlock_mutex(g_thumbnail_queue.results_lock);
	//STOP_TIMER(timer);
}

static void add_to_albums(const Track& track) {
	const char *album_name = get_metadata_string(track.metadata, METADATA_ALBUM);
	if (!strcmp(album_name, " ")) return; // Cancel if this track doesn't have an album
	uint64 id = XXH3_64bits(album_name, strlen(album_name));
	int32 album_count = g_albums.albums.length();
	int32 index;
	for (index = 0; index < album_count; ++index) {
		if (g_albums.ids[index] == id) {
			break;
		}
	}
	
	// Album doesn't exist, add it
	if (index == album_count) {
		Album album = {};
		album.metadata = track.metadata;
		album.tracks.add(track, false);
		
		index = g_albums.ids.append(id);
		g_albums.albums.append(album);
		queue_thumbnail_load(index, track.path);
	}
	else {
		Album& album = g_albums.albums[index];
		album.tracks.add(track, false);
	}
}

bool Tracklist::add(Track track, bool add_to_album_pool) {
	uint32 track_count = m_tracks.length();
	uint32 m = track_count/2;
	for (uint32 i = 0; i < m; ++i) {
		if (m_tracks[i].metadata == track.metadata) 
			return true;
		if (m_tracks[i+m].metadata == track.metadata)
			return true;
	}
	if ((track_count%2) && m_tracks[track_count-1].metadata == track.metadata) return true;
	
	m_tracks.append(track);
	ui_add_to_library(track);
	if (add_to_album_pool) add_to_albums(track);
	return true;
}

bool Tracklist::add(const char *path) {
	Track track;
	if (!stream_file_is_supported(path)) 
		return false;
	
	if (!file_exists(path)) {
		m_missing_tracks.append(store_file_path(path));
		return false;
	}

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

static Metadata_Type get_sorting_alternate_metadata_type(Metadata_Type type) {
	switch (type) {
		case METADATA_TITLE: 
		return METADATA_ALBUM;
		
		case METADATA_ALBUM:
		case METADATA_ARTIST:
		return METADATA_TITLE;
	}
	
	return METADATA_TITLE;
}

static bool track_sorts_before_track(const Track& a, const Track& b, Metadata_Type aspect) {
	const char *A = get_metadata_string(a.metadata, aspect);
	const char *B = get_metadata_string(b.metadata, aspect);
	if (!A[0]) return 0;
	if (!B[0]) return 1;
	
	int cmp = compare_strings_case_insensitive(A, B);
	if (cmp == 0) {
		aspect = get_sorting_alternate_metadata_type(aspect);
		A = get_metadata_string(a.metadata, aspect);
		B = get_metadata_string(b.metadata, aspect);
		if (!A[0]) return 0;
		if (!B[0]) return 1;
		return compare_strings_case_insensitive(A, B) == -1;
	}
	
	return cmp == -1;
}

static void quick_sort_tracks(Auto_Array<Track> tracks, int low, int high, Metadata_Type aspect) {
	int pivot;
	if (low < high) {
		pivot = high;
		{
			int i = low-1;
			for (int j = low; j <= high-1; ++j) {
				bool j_before_pivot = track_sorts_before_track(tracks[j], tracks[pivot], aspect);
				if (j_before_pivot) {
					i++;
					SWAP(tracks[i], tracks[j]);
				}
			}
			SWAP(tracks[i+1], tracks[high]);
			pivot = i + 1;
		}
		
		quick_sort_tracks(tracks, low, pivot-1, aspect);
		quick_sort_tracks(tracks, pivot+1, high, aspect);
	}
}

void Tracklist::sort(Metadata_Type aspect) {
	quick_sort_tracks(m_tracks, 0, m_tracks.m_count-1, aspect);
}

const char *Tracklist::get_filename() const {
	return m_filename;
}

void Tracklist::remove_missing_tracks() {
	m_missing_tracks.reset();
}

uint32 Tracklist::load_from_file(const char *path) {
	char line[1024];
	uint32 count = 0;
	size_t length = 0;
	char *buffer;
	const char *reader;
	
	//strncpy(m_filename, get_file_name(path), sizeof(m_filename)-1);
	strncpy(m_filename, path, sizeof(m_filename)-1);

	if (!read_whole_file_string(path, &buffer)) return 0;
	reader = buffer;
	
	// Version
	reader = read_line(reader, line, sizeof(line));
	if (!reader) return 0;

	// Name
	if (reader = read_line(reader, line, sizeof(line))) {
		length = strlen(line);
		line[length - 1] = 0;
		strncpy(this->name, line, sizeof(this->name)-1);
	}
	
	if (!reader) return 0;
	
	// Tracks
	while (reader = read_line(reader, line, sizeof(line))) {
		length = strlen(line);
		line[length - 1] = 0;
		count += this->add(line);
	}

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
	
	for (uint32 i = 0; i < m_missing_tracks.m_count; ++i) {
		char track_path[512];
		retrieve_file_path(m_missing_tracks[i], track_path, 512);
		fprintf(file, "%s\n", track_path);
	}

	fclose(file);
}

void Tracklist::delete_file() {
	if (!m_filename[0]) return;
	remove(m_filename);
}
