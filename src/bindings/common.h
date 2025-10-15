#include <stddef.h>
#include <stdint.h>
#include <limits.h>
#include <assert.h>
#include <stdlib.h>

typedef uint64_t u64;
typedef uint32_t u32;
typedef uint16_t u16;
typedef uint8_t u8;
typedef int64_t s64;
typedef int32_t s32;
typedef int16_t s16;
typedef int8_t s8;
typedef float f32;
typedef double f64;

//-
// Logging
#include <stdio.h>
#define log_error(...) printf(__VA_ARGS__)
#define log_warning(...) printf(__VA_ARGS__); putchar('\n')
#define log_info(...) printf(__VA_ARGS__); putchar('\n')
#define log_debug(...) printf(__VA_ARGS__); putchar('\n')
//-

//-
// Defer helper macro
template <typename F>
struct Defer_Holder_ {
    F f;
    Defer_Holder_(F f) : f(f) {}
    ~Defer_Holder_() { f(); }
};

template <typename F>
Defer_Holder_<F> create_defer_(F f) {
    return Defer_Holder_<F>(f);
}

#define DEFER_CAT1_(x, y) x##y
#define DEFER_CAT2_(x, y) DEFER_CAT1_(x, y)
#define DEFER_DECL_(x) DEFER_CAT2_(x, __COUNTER__)
#define defer(code) auto DEFER_DECL_(defer__) = create_defer_([&](){code;})
//-

//-
// Other helpful macros
#define ARRAY_LENGTH(arr) (sizeof(arr) / sizeof((arr)[0]))
#define CONCAT(a, b) a##b
#define WIDE_STRING(str) CONCAT(L, str)
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
//-
