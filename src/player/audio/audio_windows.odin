/*
	RAT MP: A lightweight graphical music player
    Copyright (C) 2025 Jamie Dennis

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
package audio;

import "core:log";
import win "core:sys/windows";
import "core:unicode/utf16";
import "core:thread";

import wasapi "../../bindings/wasapi";

_audio: struct {
	device_enumerator: ^wasapi.IMMDeviceEnumerator,
	device_props: []Device_Props,
	device_ids: []win.LPCWSTR,
	device_collection: ^wasapi.IMMDeviceCollection,
	selected_device_index: int,
	default_device_index: int,
	thread: ^thread.Thread,
	stream_info: Stream_Info,
	
	thread_done_event: win.HANDLE,
	thread_ready_event: win.HANDLE,
	thread_interrupt_event: win.HANDLE,
	want_stop_thread: bool,

	callback: Callback,
	callback_data: rawptr,
};

@private
_wstring_length :: proc(str: [^]u16) -> int {
	size: int;
	for i := 0;; i += 1 {
		if str[i] == 0 {return size}
		size += 1;
	}
	log.debug(size);
	return size;
}

@private
_wstring_equal :: proc(a: [^]u16, b: [^]u16) -> bool {
	for i := 0; ; i += 1 {
		if a[i] == 0 && b[i] == 0 {return true}
		else if a[i] == 0 {return false}
		else if b[i] == 0 {return false}
		else if a[i] != b[i] {return false}
	}
}

@private
_safe_release :: proc(p: ^^$T) {
	if p^ != nil {
		p^->Release();
		p^ = nil;
	}
}

@private
_check :: proc(hr: win.HRESULT, loc := #caller_location) -> bool {
	if !win.SUCCEEDED(hr) {
		log.error(loc, "HRESULT", hr);
		return false;
	}
	return true;
}

init :: proc() -> (ok: bool) {
	hr: win.HRESULT;

	defer if !ok {shutdown()}

	win.CoInitializeEx(nil, .MULTITHREADED);

	hr = win.CoCreateInstance(&wasapi.CLSID_MMDeviceEnumerator, nil, 
		win.CLSCTX_ALL, wasapi.IMMDeviceEnumerator_UUID, auto_cast &_audio.device_enumerator);
	_check(hr) or_return;

	_audio.thread_done_event = win.CreateEventW(nil, false, false, nil);
	_audio.thread_ready_event = win.CreateEventW(nil, false, false, nil);
	_audio.thread_interrupt_event = win.CreateEventW(nil, false, false, nil);

	_enumerate_devices();

	ok = true;
	return;
}

shutdown :: proc() {
	_safe_release(&_audio.device_enumerator);
	win.CloseHandle(_audio.thread_done_event);
	win.CloseHandle(_audio.thread_ready_event);
	delete(_audio.device_props);
}

get_default_device_index :: proc() -> int {
	return _audio.default_device_index;
}

start :: proc(device_index: int, callback: Callback, callback_data: rawptr) -> Stream_Info {
	_audio.selected_device_index = device_index;
	_audio.callback = callback;
	_audio.callback_data = callback_data;

	_audio.thread = thread.create_and_start(_thread_proc, context);
	win.WaitForSingleObject(_audio.thread_ready_event, win.INFINITE);

	return _audio.stream_info;
}

stop :: proc() {
	if _audio.thread == nil {return}
	_audio.want_stop_thread = true;
	win.SetEvent(_audio.thread_interrupt_event);
	win.WaitForSingleObject(_audio.thread_done_event, win.INFINITE);
	win.ResetEvent(_audio.thread_ready_event);
	win.ResetEvent(_audio.thread_done_event);
	win.ResetEvent(_audio.thread_interrupt_event);
	_audio.thread = nil;
	_audio.want_stop_thread = false;
}

interrupt :: proc() {
	win.SetEvent(_audio.thread_interrupt_event);
}

set_volume :: proc(volume: f32) {}
get_volume :: proc() -> f32 {return 1}

@private
_enumerate_devices :: proc() -> (ok: bool) {
	hr: win.HRESULT;
	count: win.UINT;
	default_device: ^wasapi.IMMDevice;
	default_device_id: win.LPCWSTR;

	delete(_audio.device_props);
	_audio.device_props = nil;

	hr = _audio.device_enumerator->EnumAudioEndpoints(.eRender, 0x1, &_audio.device_collection);
	_check(hr) or_return;

	_check(_audio.device_enumerator->GetDefaultAudioEndpoint(.eRender, .eConsole, &default_device)) or_return;
	defer default_device->Release();
	_check(default_device->GetId(&default_device_id)) or_return;
	defer win.CoTaskMemFree(default_device_id);

	_check(_audio.device_collection->GetCount(&count)) or_return;
	if count == 0 {
		return;
	}

	_audio.device_props = make([]Device_Props, count);

	for i in 0..<count {
		propstore: ^win.IPropertyStore;
		device: ^wasapi.IMMDevice;
		name_container: wasapi.PROPVARIANT;
		id: win.LPCWSTR;

		props := &_audio.device_props[i];
		
		_check(_audio.device_collection->Item(i, &device)) or_continue;
		defer device->Release();
		_check(device->OpenPropertyStore(0, &propstore)) or_continue;
		defer propstore->Release();

		propstore->GetValue(wasapi.PKEY_DeviceInterface_FriendlyName, auto_cast &name_container);

		name_ptr := name_container.val.lpwszVal;
		if name_ptr == nil {continue}
		name_len := _wstring_length(name_ptr);
		name_len = max(name_len, _MAX_DEVICE_NAME_LEN);
		name := name_ptr[:name_len];

		utf16.decode_to_utf8(props.name[:], name);
		log.debug(cstring(&props.name[0]));

		_check(device->GetId(&id)) or_continue;
		defer win.CoTaskMemFree(id);

		if _wstring_equal(id, default_device_id) {
			_audio.default_device_index = auto_cast i;
		}
	}

	ok = true;
	return;
}

@private
_run_audio_session :: proc() -> (ok: bool) {
	format: ^wasapi.WAVEFORMATEX;
	buffer_frame_count: u32;
	device: ^wasapi.IMMDevice;
	audio_client: ^wasapi.IAudioClient;
	render_client: ^wasapi.IAudioRenderClient;
	buffer: ^u8;
	buffer_duration_ms: win.DWORD;
	samplerate, channels: int;

	defer if !ok {
		win.SetEvent(_audio.thread_ready_event);
		win.SetEvent(_audio.thread_done_event);
	};

	_check(_audio.device_collection->Item(auto_cast _audio.selected_device_index, &device)) or_return;
	defer _safe_release(&device);

	_check(device->Activate(wasapi.IAudioClient_UUID, win.CLSCTX_ALL, nil, auto_cast &audio_client)) or_return;
	defer _safe_release(&audio_client);

	_check(audio_client->GetMixFormat(&format)) or_return;
	defer win.CoTaskMemFree(format);

	_check(audio_client->Initialize(.SHARED, 0, 1e7, 0, format, nil)) or_return;
	audio_client->GetBufferSize(&buffer_frame_count);
	_check(audio_client->GetService(wasapi.IAudioRenderClient_UUID, auto_cast &render_client)) or_return;
	defer _safe_release(&render_client);

	
	render_client->GetBuffer(buffer_frame_count, &buffer);
	render_client->ReleaseBuffer(buffer_frame_count, 0);
	
	buffer_duration_ms = u32(format.nSamplesPerSec*1000) / buffer_frame_count;
	
	log.debug("Buffer frames:", buffer_frame_count);
	log.debug("Buffer duration:", buffer_duration_ms, "ms");
	log.debug("Sample rate:", format.nSamplesPerSec, "Hz");

	_audio.stream_info = Stream_Info {
		buffer_duration_ms = auto_cast buffer_duration_ms,
		channels = auto_cast format.nChannels,
		sample_rate = auto_cast format.nSamplesPerSec,
	};

	// We've set the stream info. Now the calling thread can continue
	win.SetEvent(_audio.thread_ready_event);

	samplerate = auto_cast format.nSamplesPerSec;
	channels = auto_cast format.nChannels;

	audio_client->Start();
	for !_audio.want_stop_thread {
		frame_padding: u32;
		avail_frames: u32;

		if win.WaitForSingleObject(_audio.thread_interrupt_event, buffer_duration_ms/2) != win.WAIT_TIMEOUT {
			win.ResetEvent(_audio.thread_interrupt_event);
			audio_client->Stop();
			audio_client->Reset();
			audio_client->Start();
		}

		if _audio.want_stop_thread {break}

		audio_client->GetCurrentPadding(&frame_padding);
		avail_frames = buffer_frame_count - frame_padding;
		//log.debug(buffer_frame_count, frame_padding);

		render_client->GetBuffer(avail_frames, &buffer);
		_audio.callback((cast([^]f32)buffer)[:int(avail_frames)*channels], _audio.callback_data);
		render_client->ReleaseBuffer(avail_frames, 0);
	}

	win.SetEvent(_audio.thread_done_event);

	ok = true;
	return;
}

@private
_thread_proc :: proc() {
	_run_audio_session();
}

