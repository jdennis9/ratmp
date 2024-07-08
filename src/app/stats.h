#ifndef STATS_H
#define STATS_H

#include "common.h"

// Serialized do not change!
enum Stat_Counter_Type {
	STAT_COUNTER_TITLE = 0,
	STAT_COUNTER_ARTIST = 1,
	STAT_COUNTER_ALBUM = 2,
	STAT_COUNTER__COUNT,
};

uint32 get_stat_counter(Stat_Counter_Type counter, const char *string);
void increment_stat_counter(Stat_Counter_Type counter, const char *string);

#endif //STATS_H
