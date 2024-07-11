#include "stats.h"
#include "util/auto_array_impl.h"
#include "files.h"
#include <string.h>
#include <imgui.h>

struct Secondary_Counter {
	uint32 hash;
	uint32 string;
	uint32 value;
};

static Auto_Array<char> g_string_pool;
static Auto_Array<Track> g_counter_keys;
static Auto_Array<uint32> g_counters;
static Auto_Array<Secondary_Counter> g_artist_counters;
static Auto_Array<Secondary_Counter> g_album_counters;
static Mutex g_write_lock;

void init_stats() {
	g_write_lock = create_mutex();
}

static uint32 push_string(const char *str) {
	size_t length = strlen(str);
	uint32 offset = g_string_pool.push(length + 1);
	for (uint32 i = 0; i < length; ++i) {
		g_string_pool[offset + i] = str[i];
	}
	g_string_pool[offset + length] = 0;
	return offset;
}

static void increment_secondary_counter(Auto_Array<Secondary_Counter>& counters, const char *string, uint32 amount = 1) {
	uint32 hash = hash_string(string);
	for (uint32 i = 0; i < counters.m_count; ++i) {
		if (counters[i].hash == hash) {
			counters[i].value += amount;
			
			while (i && counters[i-1].value < counters[i].value) {
				SWAP(counters[i], counters[i-1]);
				i--;
			}
			
			return;
		}
	}
	
	Secondary_Counter c;
	c.hash = hash;
	c.string = push_string(string);
	c.value = amount;
	
	counters.append(c);
}

static int lookup_track_counter(const Track& track) {
	for (uint32 i = 0; i < g_counter_keys.m_count; ++i) {
		if (g_counter_keys[i].metadata == track.metadata) return i;
	}
	return -1;
}

void increment_track_play_count(const Track& track, uint32 amount) {
	int index = lookup_track_counter(track);
	if (index == -1) {
		index = g_counter_keys.append(track);
		g_counters.append(amount);
	}
	else {
		g_counters[index] += amount;
		while (index && g_counters[index-1] < g_counters[index]) {
			SWAP(g_counter_keys[index-1], g_counter_keys[index]);
			SWAP(g_counters[index-1], g_counters[index]);
			index--;
		}
	}
	
	const char *artist = get_metadata_string(track.metadata, METADATA_ARTIST);
	const char *album = get_metadata_string(track.metadata, METADATA_ALBUM);
	if (!metadata_string_is_empty(artist)) increment_secondary_counter(g_artist_counters, artist, amount);
	if (!metadata_string_is_empty(album)) increment_secondary_counter(g_album_counters, album, amount);
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
	g_artist_counters.reset();
	g_album_counters.reset();
	
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
		increment_track_play_count(track, count);
	}
	
	free(buffer);
}

void show_secondary_counter_gui(const char *table_name, const char *header_name, 
								const Auto_Array<Secondary_Counter>& counters) {
	if (ImGui::BeginTable(table_name, 2, ImGuiTableFlags_RowBg)) {
		ImGui::TableSetupScrollFreeze(1, 1);
		ImGui::TableHeadersRow();
		ImGui::TableSetColumnIndex(0);
		ImGui::TableHeader(header_name);
		ImGui::TableSetColumnIndex(1);
		ImGui::TableHeader("No. Plays");
		for (uint32 i = 0; i < counters.m_count; ++i) {
			ImGui::TableNextRow();
			ImGui::TableSetColumnIndex(0);
			ImGui::TextUnformatted(&g_string_pool[counters[i].string]);
			ImGui::TableSetColumnIndex(1);
			ImGui::Text("%u", counters[i].value);
		}
		ImGui::EndTable();
	}
}

void show_playback_stats_gui() {
	lock_mutex(g_write_lock);
	if (ImGui::BeginTabBar("##stats_tabs")) {
		if (ImGui::BeginTabItem("Tracks")) {
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
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Artists")) {
			show_secondary_counter_gui("##artist_counters", "Artist", g_artist_counters);
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Albums")) {
			show_secondary_counter_gui("##album_counters", "Album", g_album_counters);
			ImGui::EndTabItem();
		}
		ImGui::EndTabBar();
	}
	unlock_mutex(g_write_lock);
}
