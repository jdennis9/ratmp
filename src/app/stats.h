#ifndef STATS_H
#define STATS_H

#include "common.h"
#include "tracklist.h"

void init_stats();
void increment_track_play_count(const Track& track, uint32 amount = 1);
uint32 get_track_play_count(const Track& track);
void save_stats();
void load_stats();
void show_playback_stats_gui();

#endif //STATS_H
