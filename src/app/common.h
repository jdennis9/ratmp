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

#define VERSION_STRING "1.0.2"
#define ARRAY_LENGTH(array) (sizeof(array) / sizeof((array)[0]))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define SWAP(a, b) {auto swapper_ = a; a = b; b = swapper_;}

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

typedef void *Texture_ID;

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

Texture_ID create_texture_from_image(const Image *image);
void destroy_texture(Texture_ID texture);

uint64 time_get_tick();
uint64 time_get_frequency();
uint32 wchar_to_multibyte(const wchar_t *in, char *out, uint32 out_max);
uint32 multibyte_to_wchar(const char *in, wchar_t *out, uint32 out_max);
int format_time(int32 seconds, char *buffer, int buffer_size);

enum Message_Box_Type {
	MESSAGE_BOX_ERROR,
	MESSAGE_BOX_WARNING,
	MESSAGE_BOX_INFO,
	MESSAGE_BOX__COUNT,
};

void show_message_box(Message_Box_Type type, const char *message, ...);

#define USER_ASSERT_WARN(cond, ...) if (!(cond)) show_message_box(MESSAGE_BOX_WARNING, __VA_ARGS__)
#define USER_ASSERT_FATAL(cond, ...) if (!(cond)) { show_message_box(MESSAGE_BOX_ERROR, __VA_ARGS__); exit(0); }

#endif //COMMON_H
