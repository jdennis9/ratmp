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
#ifndef UTIL_H
#define UTIL_H

#include "common.h"

template <typename F>
struct Defer_Holder {
	F f;
	Defer_Holder(F f) : f(f) {}
	~Defer_Holder() { f(); }
};

template <typename F>
Defer_Holder<F> create_defer_(F f) {
	return Defer_Holder<F>(f);
}

#define DEFER_CAT1_(x, y) x##y
#define DEFER_CAT2_(x, y) DEFER_CAT1_(x, y)
#define DEFER_DECL_(x) DEFER_CAT2_(x, __COUNTER__)
#define defer(code) auto DEFER_DECL_(defer__) = create_defer_([&](){code;})

#endif //UTIL_H
