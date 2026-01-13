#ifndef MEDIA_CONTROLS_H_
#define MEDIA_CONTROLS_H_

#include <stdint.h>

enum {
	SIGNAL_PLAY,
	SIGNAL_PAUSE,
	SIGNAL_STOP,
	SIGNAL_NEXT,
	SIGNAL_PREV,
};

enum {
	STATE_PLAYING,
	STATE_PAUSED,
	STATE_STOPPED,
};

struct Track_Info {
	const char *path;
	const char *artist;
	const char *album;
	const char *title;
	const char *genre;
	const uint8_t *cover_data;
	uint32_t cover_data_size;
};

typedef void Handler(void *data, int32_t signal);

extern "C" {
	void enable(Handler *handler, void *data);
	void disable();
	void set_state(int32_t state);
	void set_metadata(const char *artist, const char *album, const char *title);
	void set_track_info(const Track_Info *info);
};

#endif
