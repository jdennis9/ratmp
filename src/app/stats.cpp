#include "stats.h"
#include "util/auto_array_impl.h"
#include "files.h"
#include <string.h>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

struct Stat_Counter_Key {
	uint32 key;
	Stat_Counter_Type type;
};

struct Stat_Counter {
	uint32 string;
	uint32 value;
};

static Auto_Array<char> g_string_pool;
static Auto_Array<Stat_Counter_Key> g_counter_keys;
static Auto_Array<Stat_Counter> g_counters;
static Mutex g_write_lock;

static uint32 push_string(const char *str) {
	size_t length = strlen(str);
	uint32 offset = g_string_pool.push(length + 1);
	for (uint32 i = 0; i < length; ++i) {
		g_string_pool[offset + i] = str[i];
	}
	g_string_pool[offset + length] = 0;
	return offset;
}

void init_stats() {
	g_write_lock = create_mutex();
}

int lookup_stat_counter(Stat_Counter_Type type, const char *string) {
	uint32 key = hash_string(string);
	for (uint32 i = 0; i < g_counter_keys.m_count; ++i) {
		if (g_counter_keys[i].key == key && g_counter_keys[i].type == type) {
			return i;
		}
	}
	
	return -1;
}

uint32 get_stat_counter(Stat_Counter_Type type, const char *string) {
	int index = lookup_stat_counter(type, string);
	return index >= 0 ? g_counters[index].value : 0;
}

void increment_stat_counter(Stat_Counter_Type type, const char *string) {
	lock_mutex(g_write_lock);
	int index = lookup_stat_counter(type, string);
	if (index < 0) {
		index = g_counter_keys.push(1);
		g_counters.push(1);
		g_counter_keys[index].key = hash_string(string);
		g_counter_keys[index].type = type;
		g_counters[index].string = push_string(string);
		g_counters[index].value = 0;
	}
	
	g_counters[index].value++;
	unlock_mutex(g_write_lock);
}

static DWORD WINAPI async_save_stats(LPVOID dont_care) {
	if (!file_exists("stats")) {
		if (!create_directory("stats")) return 0;
	}
	
	lock_mutex(g_write_lock);
	FILE *f = fopen("stats/counters", "w");
	if (f) {
		// Version
		fprintf(f, "1\n");
		
		for (uint32 i = 0; i < g_counters.m_count; ++i) {
			const char *string = &g_string_pool[g_counters[i].string];
			fprintf(f, "%d %u %s\n", g_counter_keys[i].type, g_counters[i].value,
					string);
		}
		
		fclose(f);
	}
	unlock_mutex(g_write_lock);
	return 0;
}

static DWORD WINAPI async_load_stats(LPVOID dont_care) {
	lock_mutex(g_write_lock);
	FILE *f = fopen("stats/counters", "r");
	char line[1024];
	if (f) {
		g_string_pool.reset();
		g_counter_keys.reset();
		g_counters.reset();
		
		fgets(line, sizeof(line), f);
		
		while (fgets(line, sizeof(line), f)) {
			char *string = line;
			int type;
			int count;
			
			line[strlen(line)-1] = 0;
			
			string = strtok(string, " ");
			if (!string) continue;
			type = atoi(string);
			string += strlen(string)+1;
			if (!*string) continue;
			//string = eat_spaces(string);
			
			string = strtok(string, " ");
			if (!string) continue;
			count = atoi(string);
			string += strlen(string)+1;
			if (!*string) continue;
			//string = eat_spaces(string);
			
			if (!*string) continue;
			
			int index = g_counter_keys.push(1);
			g_counters.push(1);
			
			g_counter_keys[index].key = hash_string(string);
			g_counter_keys[index].type = (Stat_Counter_Type)type;
			g_counters[index].string = push_string(string);
			g_counters[index].value = count;
			
			log_debug("\"%s\" : %d, %d\n", string, type, count);
		}
		fclose(f);
	}
	unlock_mutex(g_write_lock);
	return 0;
}

void save_stats() {
	CreateThread(NULL, 0, &async_save_stats, NULL, 0, NULL);
}

void load_stats() {	
	CreateThread(NULL, 0, &async_load_stats, NULL, 0, NULL);
}


