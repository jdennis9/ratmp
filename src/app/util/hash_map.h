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
#ifndef HASH_MAP_H
#define HASH_MAP_H

#include "../common.h"

template<typename T>
class Hash_Map {
	public:
	using Key = uint32;

	struct Pair {
		Key key;
		T value;
	};
	
	private:
	Key *m_keys;
	T *m_values;
	uint32 m_count;
	uint32 m_capacity;
	
	uint32 push(uint32 count);
	
	public:
	
	INLINE Pair operator [](int index) const {
		return Pair{m_keys[index], m_values[index]};
	}
	
	uint32 add(const char *key, T const& value);
	uint32 add(Key key, T const& value);
	int32 lookup(Key key) const;
	int32 lookup(const char *key) const;
	T lookup(const char *key, T const& not_found) const;
	T lookup(Key key, T const& not_found) const;

	uint32 length() const;
	void reset();
	void free();
	
	static Key hash(const char *key);
};

#endif //HASH_MAP_H
