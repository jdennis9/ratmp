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
#ifndef AUTO_ARRAY_H
#define AUTO_ARRAY_H

#include "../common.h"

template<typename T>
struct Auto_Array {
	uint32 m_count;
	uint32 m_capacity;
	T *m_elements;
	
	INLINE T& operator [](int64 index) {return m_elements[index];}
	INLINE const T& operator [](int64 index) const {return m_elements[index];}
	
	inline uint32 push(uint32 count);
	inline uint32 append(T const& elem);
	inline uint32 length() const;
	inline void remove(uint32 index);
	inline void remove_range(int32 first, int32 last);
	inline void reset();
	inline void free();
	inline void copy_to(Auto_Array<T>& other);
};

#endif //AUTO_ARRAY_H
