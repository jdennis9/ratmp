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
#ifndef HASH_MAP_IMPL_H
#define HASH_MAP_IMPL_H

#include "hash_map.h"
#include <xxhash.h>

#define HASH_STRING(str) XXH32(str, strlen(str), 0)

template<typename T>
inline typename Hash_Map<T>::Key Hash_Map<T>::hash(const char *key) {
	return HASH_STRING(key);
}

template<typename T>
inline uint32 Hash_Map<T>::push(uint32 count) {
	uint32 index = m_count;
	if (m_count + count >= m_capacity) {
		uint32 elements_per_page = 4096/sizeof(T);
		uint32 new_capacity = m_capacity + elements_per_page;
		while (new_capacity <= (m_count + count)) new_capacity += elements_per_page;
		m_values = (T*)realloc(m_values, sizeof(T) * new_capacity);
		m_keys = (Key*)realloc(m_keys, sizeof(Key) * new_capacity);
		m_capacity = new_capacity;
	}
	m_count += count;
	return index;
}

template<typename T>
inline uint32 Hash_Map<T>::add(Key key, T const& value) {
	uint32 index = this->push(1);
	m_keys[index] = key;
	m_values[index] = value;
	return index;
}

template<typename T>
inline uint32 Hash_Map<T>::add(const char *key, T const& value) {
	return this->add(Hash_Map::hash(key), value); 
}

template<typename T>
inline T Hash_Map<T>::lookup(Key key, T const& not_found) const {
	uint32 m = m_count/2;
	
	for (uint32 i = 0; i < m; ++i) {
		if (m_keys[i] == key) return m_values[i];
		else if (m_keys[i+m] == key) return m_values[i+m];
	}
	
	if ((m_count%2) && (m_keys[m_count-1] == key)) return m_values[m_count-1];
	
	return not_found;
}

template<typename T>
inline T Hash_Map<T>::lookup(const char *key, T const& not_found) const {
	return this->lookup(Hash_Map::hash(key), not_found);
}

template<typename T>
inline int32 Hash_Map<T>::lookup(Key key) const {
	uint32 m = m_count / 2;

	for (uint32 i = 0; i < m; ++i) {
		if (m_keys[i] == key) {
			return i;
		}
		else if (m_keys[i + m] == key) {
			return i + m;
		}
	}

	if ((m_count % 2) && (m_keys[m_count - 1] == key)) {
		return m_count - 1;
	}

	return -1;
}

template<typename T>
inline int32 Hash_Map<T>::lookup(const char *key) const {
	return this->lookup(Hash_Map::hash(key));
}

template<typename T>
inline uint32 Hash_Map<T>::length() const {
	return m_count;
}

template<typename T>
inline void Hash_Map<T>::reset() {
	m_count = 0;
}

template<typename T>
inline void Hash_Map<T>::free() {
	free(m_keys);
	free(m_values);
	m_count = 0;
	m_capacity = 0;
}

#endif //HASH_MAP_IMPL_H
