#ifndef MEDIA_CONTROLS_H_
#define MEDIA_CONTROLS_H_

#include <stdint.h>

enum {
	SIGNAL_PLAY,
	SIGNAL_PAUSE,
	SIGNAL_STOP,
	SIGNAL_NEXT,
	SIGNAL_PREV,
	SIGNAL_ENABLE_SHUFFLE,
	SIGNAL_DISABLE_SHUFFLE,
};

struct State {
	bool paused;
	bool shuffle;
	bool have_track;
};

struct Track_Info {
	const char *artist;
	const char *album;
	const char *title;
	const char *genre;
	const void *cover_data;
	uint32_t cover_data_size;
};

typedef void Handler(void *data, int32_t signal);

extern "C" {
	void smtc_create(Handler *handler, void *data);
	void smtc_destroy();
	void smtc_set_state(State *state);
	void smtc_set_track_info(const Track_Info *info);
};

#endif
