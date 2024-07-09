#include "stats.h"
#include "util/auto_array_impl.h"
#include "files.h"
#include <string.h>
#include <imgui.h>

static Auto_Array<Track> g_counter_keys;
static Auto_Array<uint32> g_counters;
static Mutex g_write_lock;

void init_stats() {
	g_write_lock = create_mutex();
}

static int lookup_track_counter(const Track& track) {
	for (uint32 i = 0; i < g_counter_keys.m_count; ++i) {
		if (g_counter_keys[i].metadata == track.metadata) return i;
	}
	return -1;
}

void increment_track_play_count(const Track& track) {
	int index = lookup_track_counter(track);
	if (index == -1) {
		index = g_counter_keys.append(track);
		g_counters.append(1);
	}
	else {
		g_counters[index]++;
		while (index && g_counters[index-1] < g_counters[index]) {
			SWAP(g_counter_keys[index-1], g_counter_keys[index]);
			SWAP(g_counters[index-1], g_counters[index]);
			index--;
		}
	}
}

uint32 get_track_play_count(const Track& track) {
	int index = lookup_track_counter(track);
	if (index == -1) return 0;
	return g_counters[index];
}

void save_stats() {
	if (!file_exists("stats")) {
		create_directory("stats");
	}
	FILE *f = fopen("stats/counters", "w");
	if (!f) return;
	
	fprintf(f, "1\n");
	
	for (uint32 i = 0; i < g_counters.m_count; ++i) {
		char path[512];
		retrieve_file_path(g_counter_keys[i].path, path, sizeof(path));
		fprintf(f, "%u %s\n", g_counters[i], path);
	}
	
	fclose(f);
}

void load_stats() {
	char *buffer;
	if (!read_whole_file_string("stats/counters", &buffer)) return;
	
	g_counter_keys.reset();
	g_counters.reset();
	
	char line[1024];
	const char *reader = buffer;
	
	// Version
	reader = read_line(reader, line, sizeof(line));
	if (!reader) return;
	
	while (reader = read_line(reader, line, sizeof(line))) {
		char *string = line;
		line[strlen(line) - 1] = 0;
		string = strtok(string, " ");
		if (!string || !*string) continue;
		int count = atoi(string);
		const char *path = string + strlen(string) + 1;
		if (!*path) continue;
		
		Track track;
		track.path = store_file_path(path);
		track.metadata = retrieve_metadata(path);
		g_counter_keys.append(track);
		g_counters.append(count);
	}
	
	free(buffer);
}

void show_playback_stats_gui() {
	lock_mutex(g_write_lock);
	if (ImGui::BeginTable("##track_table", 4, ImGuiTableFlags_RowBg)) {
		ImGui::TableSetupScrollFreeze(1, 1);
		ImGui::TableHeadersRow();
		ImGui::TableSetColumnIndex(0);
		ImGui::TableHeader("No. Plays");
		ImGui::TableSetColumnIndex(1);
		ImGui::TableHeader("Album");
		ImGui::TableSetColumnIndex(2);
		ImGui::TableHeader("Artist");
		ImGui::TableSetColumnIndex(3);
		ImGui::TableHeader("Track");
		
		for (uint32 i = 0; i < g_counter_keys.m_count; ++i) {
			ImGui::TableNextRow();
			const Track& track = g_counter_keys[i];
			const char *album = get_metadata_string(track.metadata, METADATA_ALBUM);
			const char *artist = get_metadata_string(track.metadata, METADATA_ARTIST);
			const char *title = get_metadata_string(track.metadata, METADATA_TITLE);
			ImGui::TableSetColumnIndex(0);
			ImGui::Text("%u", g_counters[i]);
			ImGui::TableSetColumnIndex(1);
			ImGui::TextUnformatted(album);
			ImGui::TableSetColumnIndex(2);
			ImGui::TextUnformatted(artist);
			ImGui::TableSetColumnIndex(3);
			ImGui::TextUnformatted(title);
			//ImGui::Text("%s - %s : %u", artist, title, g_counters[i]);
		}
		ImGui::EndTable();
	}
	unlock_mutex(g_write_lock);
}
