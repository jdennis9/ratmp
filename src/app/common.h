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
#ifndef COMMON_H
#define COMMON_H

#pragma warning(disable: 4244)
#pragma warning(disable: 4267)

#include <stdint.h>
#include <limits.h>
#include <stdio.h>
#include <xxhash.h>
#include <ctype.h>

#define VERSION_STRING "1.3.0"
#define ARRAY_LENGTH(array) (sizeof(array) / sizeof((array)[0]))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define SWAP(a, b) {auto swapper_ = a; a = b; b = swapper_;}
#define hash_string(str) XXH32(str, strlen(str), 0)

#ifdef _MSC_VER
#define ALIGNED(x) __declspec(align(x))
#define INLINE __forceinline
#elif defined(__GNUC__)
#define ALIGNED(x) __attribute__((aligned(x)))
#define INLINE __attribute__((always_inline))
#endif

typedef uint64_t uint64;
typedef uint32_t uint32;
typedef uint16_t uint16;
typedef uint8_t uint8;

typedef int64_t int64;
typedef int32_t int32;
typedef int16_t int16;
typedef int8_t int8;

struct ID3D10ShaderResourceView;
typedef ID3D10ShaderResourceView Texture;

struct Image {
	void *data;
	int width;
	int height;
};

#define log_debug(...) printf(__VA_ARGS__)
#define log_error(...) printf(__VA_ARGS__)

typedef void *Mutex;

Mutex create_mutex();
void lock_mutex(Mutex mtx);
void unlock_mutex(Mutex mtx);
void destroy_mutex(Mutex mtx);

typedef void *Event;
Event create_event();
void event_signal(Event event);
void event_wait(Event event);
void destroy_event(Event event);

uint64 time_get_tick();
uint64 time_get_frequency();
uint32 wchar_to_multibyte(const wchar_t *in, char *out, uint32 out_max);
uint32 multibyte_to_wchar(const char *in, wchar_t *out, uint32 out_max);
int format_time(int32 seconds, char *buffer, int buffer_size);

Texture *create_texture_from_image(const Image *image);
void destroy_texture(Texture *texture);

// Formats a thread-local global buffer and returns a pointer to it
const char *lazy_format(const char *fmt, ...);

#define START_TIMER(var, text) struct {const char *name; uint64 start;} timer__##var = {text, time_get_tick()};
#define STOP_TIMER(var) \
printf("%s: %gms\n", timer__##var.name, \
((float)(time_get_tick() - timer__##var.start) / (float)time_get_frequency()) * 1000.f);

enum Message_Box_Type {
	MESSAGE_BOX_ERROR,
	MESSAGE_BOX_WARNING,
	MESSAGE_BOX_INFO,
	MESSAGE_BOX__COUNT,
};

void show_message_box(Message_Box_Type type, const char *message, ...);

#define USER_ASSERT_WARN(cond, ...) if (!(cond)) show_message_box(MESSAGE_BOX_WARNING, __VA_ARGS__)
#define USER_ASSERT_FATAL(cond, ...) if (!(cond)) { show_message_box(MESSAGE_BOX_ERROR, __VA_ARGS__); exit(0); }

typedef int Thread_Function(void *data);
bool create_thread(Thread_Function *func, void *data);

static inline char *eat_spaces(char *c) {
	for (; *c && isspace(*c); ++c);
	return c;
}

static inline int iclamp(int i, int min, int max) {
	return (i < min) ? min : ((i > max) ? max : i);
}

#endif //COMMON_H
