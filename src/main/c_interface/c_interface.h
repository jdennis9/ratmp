#ifndef RATMP_H_
#define RATMP_H_

#include <stdint.h>

#define RATMP_API extern "C"

enum RATMP_Shared_String_Type {
	RATMP_SHARED_STRING_ARTIST,
	RATMP_SHARED_STRING_ALBUM,
	RATMP_SHARED_STRING_GENRE,
};

typedef uint32_t RATMP_Track_ID;
typedef int16_t  RATMP_Shared_String_ID;
typedef uint64_t RATMP_Playlist_ID;

struct RATMP_String {
	const char *data;
	int         len;
};

struct RATMP_Track {
	RATMP_String            url;
	RATMP_String            title;
	RATMP_Shared_String_ID *artists;
	RATMP_Shared_String_ID *genres;
	int32_t                 artist_count;
	int32_t                 genre_count;
	int32_t                 track;
	int32_t                 bitrate;
	int32_t                 channels;
	int32_t                 samplerate;
	int32_t                 duration;
	int32_t                 year;
	int64_t                 file_date;
	int64_t                 file_size;
	RATMP_Shared_String_ID  album;
	bool                    has_album;
};

struct RATMP_FFT_State;

RATMP_API bool             ratmp_init();
RATMP_API void             ratmp_shutdown();
RATMP_API void             ratmp_free(const void *ptr);
RATMP_API bool             ratmp_play_file(RATMP_String path);
RATMP_API void             ratmp_pause();
RATMP_API bool             ratmp_is_paused();
RATMP_API void             ratmp_resume();
RATMP_API void             ratmp_next();
RATMP_API void             ratmp_prev();
RATMP_API bool             ratmp_get_track(RATMP_Track_ID id, RATMP_Track *track);
RATMP_API int              ratmp_get_all_track_ids(RATMP_Track_ID **out);
RATMP_API RATMP_String     ratmp_get_shared_string(RATMP_Shared_String_Type type, RATMP_Shared_String_ID id);
RATMP_API void             ratmp_play_playlist(const RATMP_Track_ID *tracks, int track_count, RATMP_Playlist_ID id);
RATMP_API void             ratmp_consume_output(float **buffer, int buffer_channels, int buffer_size, float timespan, int *samplerate, int *channels);
RATMP_API RATMP_FFT_State *ratmp_new_fft();
RATMP_API void             ratmp_destroy_fft(RATMP_FFT_State *state);
RATMP_API void             ratmp_fft(RATMP_FFT_State *state, float *input, int input_count, float **output, int *output_count);

#endif
