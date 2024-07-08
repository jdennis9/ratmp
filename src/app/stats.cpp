#include "stats.h"
#include "util/auto_array_impl.h"
#include <string.h>

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

static uint32 push_string(const char *str) {
	size_t length = strlen(str);
	uint32 offset = g_string_pool.push(length + 1);
	for (uint32 i = 0; i < length; ++i) {
		g_string_pool[offset + i] = str[i];
	}
	g_string_pool[offset + length] = 0;
	return offset;
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
}
