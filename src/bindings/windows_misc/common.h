#include <stdint.h>

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
