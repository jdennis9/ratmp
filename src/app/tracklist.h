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
#ifndef TRACK_LIST_H
#define TRACK_LIST_H

#include "common.h"
#include "files.h"
#include "metadata.h"
#include "util/auto_array.h"
#include "stream.h"
#include <ctype.h>

enum Track_Filter_Part {
	TRACK_FILTER_TITLE,
	TRACK_FILTER_ARTIST,
	TRACK_FILTER_ALBUM,
	TRACK_FILTER__COUNT,
};

static bool string_contains(const char *haystack, const char *needle) {
	const char *n, *h;

	for (; *haystack; ++haystack) {
		n = needle;
		h = haystack;
		while (*h && (tolower(*h) == tolower(*n))) {
			n++;
			h++;
			if (*n == 0) return true;
		}
	}

	return false;
}

struct Track_Filter {
	uint32 enabled;
	const char *filter;

	inline void add(Track_Filter_Part part) { enabled |= 1 << part; }
	inline void remove(Track_Filter_Part part) { enabled &= ~(1 << part); }
	inline bool has(Track_Filter_Part part) const { return (enabled & (1 << part)) != 0; }

	inline bool check(const char *album, const char *artist, const char *title) const {
		if (has(TRACK_FILTER_ALBUM) && string_contains(album, filter)) return true;
		if (has(TRACK_FILTER_ARTIST) && string_contains(artist, filter)) return true;
		if (has(TRACK_FILTER_TITLE) && string_contains(title, filter)) return true;
		return false;
	}
};

struct Track {
	Path_Ref path;
	Metadata_Ref metadata;
};

struct Tracklist {	
	Auto_Array<Track> m_tracks;
	struct { int32 first; int32 last; } m_selection;

	INLINE Track &operator [](int index) { return m_tracks[index]; }
	INLINE const Track &operator [](int index) const { return m_tracks[index]; }

	char name[128-16];
	char m_filename[128];

	// Get position as if repeat mode is on
	inline uint32 repeat(int32 position) const {
		int32 track_count = m_tracks.length();
		if (!track_count) return 0;
		if (position >= track_count)
			//position -= (position / (track_count - 1)) * track_count;
			return 0;
		else if (position < 0) position = 0;
		return position;
	}

	inline bool track_is_selected(int32 index) {
		return (index >= m_selection.first) && (index <= m_selection.last);
	}

	int32 index_of_track(const Track &track);
	bool add(const char *path);
	bool add(Track track, bool add_to_album_pool = true);
	uint32 length() const;
	void copy(Tracklist *dst) const;
	void copy_selection(Tracklist *dst) const;
	void copy_with_filter(Tracklist *dst, const Track_Filter *filter) const;
	void remove_selection();
	void select(int32 index);
	void select_to(int32 index);
	void shuffle();
	void clear();
	void sort(Metadata_Type aspect);
	const char *get_filename() const;

	// Returns number of tracks loaded.
	uint32 load_from_file(const char *path);
	// If path is NULL, creates a randomly named file inside the playlists folder
	void save_to_file(const char *path = NULL);
	void delete_file();
};

struct Album {
	// References the metadata for the first track of each album. The album name can be extracted from there
	Metadata_Ref metadata;
	// Thumbnail is loaded when this album is first added
	Texture_ID thumbnail;
	Tracklist tracks;
};

const Auto_Array<Album> &get_albums();

#endif //TRACK_LIST_H
