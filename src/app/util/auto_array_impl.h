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
#ifndef AUTO_ARRAY_IMPL_H
#define AUTO_ARRAY_IMPL_H

#include "auto_array.h"
#include <stdlib.h>
#include <assert.h>

template<typename T>
inline uint32 Auto_Array<T>::push(uint32 count) {
	uint32 index = m_count;
	if (m_count + count >= m_capacity) {
		uint32 elements_per_page = 4096/sizeof(T);
		uint32 new_capacity = m_capacity + elements_per_page;
		while (new_capacity <= (m_count + count)) new_capacity += elements_per_page;
		m_elements = (T*)realloc(m_elements, sizeof(T) * new_capacity);
		m_capacity = new_capacity;
	}
	m_count += count;
	return index;
}

template<typename T>
inline uint32 Auto_Array<T>::append(T const& elem) {
	uint32 index = this->push(1);
	m_elements[index] = elem;
	return index;
}

template<typename T>
inline void Auto_Array<T>::remove(uint32 index) {
	assert(index < m_count);
	m_elements[index] = m_elements[m_count-1];
	m_count--;
}

template<typename T>
inline void Auto_Array<T>::remove_range(int32 first, int32 last) {
	int32 range = last - first + 1;
	int32 count = m_count - last - 1;
	if (count) {
		memmove(&m_elements[first], &m_elements[last + 1], count * sizeof(T));
	}
	m_count -= range;
}

template<typename T>
inline uint32 Auto_Array<T>::length() const {
	return m_count;
}

template<typename T>
inline void Auto_Array<T>::reset() {
	m_count = 0;
}

template<typename T>
inline void Auto_Array<T>::free() {
	if (m_elements) {
		::free(m_elements);
		m_elements = nullptr;
	}
	m_capacity = 0;
	m_count = 0;
}

template<typename T>
inline void Auto_Array<T>::copy_to(Auto_Array<T>& other) {
	uint32 offset = other.push(m_count);
	for (uint32 i = 0; i < m_count; ++i) other[offset+i] = m_elements[i];
}
#endif

