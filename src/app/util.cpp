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
#include "common.h"

int format_time(int32 ts, char *buffer, int buffer_size) {
	int64 hours = ts / 3600;
	int64 minutes = (ts / 60) - (hours * 60);
	int64 seconds = ts - (hours * 3600) - (minutes * 60);
	return snprintf(buffer, buffer_size, "%02lld:%02lld:%02lld", hours, minutes, seconds);
}
