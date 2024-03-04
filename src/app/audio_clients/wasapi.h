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
#ifndef WASAPI_H
#define WASAPI_H

#include "../audio_client.h"

bool wasapi_init();
uint32 wasapi_get_device_count();
void wasapi_get_device_name(uint32 index, Audio_Device_Name name);
uint32 wasapi_get_default_device();
Audio_Client_Stream *wasapi_open_device(uint32 device_index, Audio_Stream_Callback *callback, void *callback_data);
void wasapi_close_device();
void wasapi_set_volume(float volume);
void wasapi_interrupt();
void wasapi_destroy();

#endif //WASAPI_H
