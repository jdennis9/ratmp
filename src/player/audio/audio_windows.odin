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
package audio

import "core:log"
import win "core:sys/windows"
import "core:unicode/utf16"
import "core:thread"

import wasapi "bindings:wasapi"

_audio: struct {
	device_enumerator: ^wasapi.IMMDeviceEnumerator,
}

Stream :: struct {
	using com: _Stream_Common,
	_wasapi: struct {
		device_id: [len(Device_ID)]u16,
		// Released by audio thread
		volume_control: ^wasapi.ISimpleAudioVolume,
		thread_done_event: win.HANDLE,
		thread_ready_event: win.HANDLE,
		thread_interrupt_event: win.HANDLE,
		want_stop_thread: bool,
		thread: ^thread.Thread,
	}
}

@private
_wstring_length :: proc(str: [^]u16) -> int {
	size: int
	for i := 0;; i += 1 {
		if str[i] == 0 {return size}
		size += 1
	}
	log.debug(size)
	return size
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
		p^->Release()
		p^ = nil
	}
}

@private
_check :: proc(hr: win.HRESULT, loc := #caller_location) -> bool {
	if !win.SUCCEEDED(hr) {
		log.error(loc, "HRESULT", hr)
		log.errorf("%x", cast(u32) hr)
		when ODIN_DEBUG {
			panic("Windows function returned an error code")
		}
		return false
	}
	return true
}

init :: proc() -> (ok: bool) {
	hr: win.HRESULT

	defer if !ok {shutdown()}

	win.CoInitializeEx(nil)

	hr = win.CoCreateInstance(&wasapi.CLSID_MMDeviceEnumerator, nil, 
		win.CLSCTX_ALL, wasapi.IMMDeviceEnumerator_UUID, auto_cast &_audio.device_enumerator)
	_check(hr) or_return

	ok = true
	return
}

shutdown :: proc() {
	_safe_release(&_audio.device_enumerator)
}

open_stream :: proc(device_id_arg: ^Device_ID, callback: Callback, callback_data: rawptr) -> (stream: ^Stream, ok: bool) {
	device_id := device_id_arg != nil ? device_id_arg^ : get_default_device_id() or_return

	stream = new(Stream)
	defer if !ok {free(stream)}

	stream._callback = callback
	stream._callback_data = callback_data

	stream._wasapi.thread_done_event = win.CreateEventW(nil, false, false, nil)
	stream._wasapi.thread_ready_event = win.CreateEventW(nil, false, false, nil)
	stream._wasapi.thread_interrupt_event = win.CreateEventW(nil, false, false, nil)

	// Encode device ID
	utf16.encode_string(stream._wasapi.device_id[:len(Device_ID)-1], string(cstring(&device_id[0])))

	stream._wasapi.thread = thread.create(_thread_proc)
	stream._wasapi.thread.data = stream
	thread.start(stream._wasapi.thread)
	win.WaitForSingleObject(stream._wasapi.thread_ready_event, win.INFINITE)

	ok = true
	return
}

close_stream :: proc(stream: ^Stream) {
	if stream._wasapi.thread == nil {return}
	stream._wasapi.want_stop_thread = true
	win.SetEvent(stream._wasapi.thread_interrupt_event)
	win.WaitForSingleObject(stream._wasapi.thread_done_event, win.INFINITE)
	win.CloseHandle(stream._wasapi.thread_ready_event)
	win.CloseHandle(stream._wasapi.thread_done_event)
	win.CloseHandle(stream._wasapi.thread_interrupt_event)
	thread.destroy(stream._wasapi.thread)
	stream._wasapi.thread = nil
	stream._wasapi.want_stop_thread = false
	free(stream)
}

stream_interrupt :: proc(stream: ^Stream) {
	win.SetEvent(stream._wasapi.thread_interrupt_event)
}

stream_set_volume :: proc(stream: ^Stream, volume: f32) {
	if stream._wasapi.volume_control != nil {
		stream._wasapi.volume_control->SetMasterVolume(volume, nil)
	}
}

stream_get_volume :: proc(stream: ^Stream) -> (volume: f32 = 1) {
	if stream._wasapi.volume_control != nil {
		stream._wasapi.volume_control->GetMasterVolume(&volume)
	}
	return
}

enumerate_devices :: proc() -> (props_list: []Device_Props, ok: bool) {
	hr: win.HRESULT
	device_count: win.UINT
	device_collection: ^wasapi.IMMDeviceCollection

	hr = _audio.device_enumerator->EnumAudioEndpoints(.eRender, 0x1, &device_collection)
	_check(hr) or_return
	_check(device_collection->GetCount(&device_count)) or_return
	if device_count == 0 {return}
	props_list = make([]Device_Props, device_count)
	defer if !ok {delete(props_list)}

	for &props, device_index in props_list {
		property_store: ^win.IPropertyStore
		device: ^wasapi.IMMDevice
		name_propvar: wasapi.PROPVARIANT
		id: win.LPCWSTR

		_check(device_collection->Item(auto_cast device_index, &device)) or_continue
		defer device->Release()
		_check(device->OpenPropertyStore(0, &property_store)) or_continue
		defer property_store->Release()
		_check(property_store->GetValue(wasapi.PKEY_DeviceInterface_FriendlyName, auto_cast &name_propvar)) or_continue
		_check(device->GetId(&id)) or_continue
		defer win.CoTaskMemFree(id)

		id_len := _wstring_length(id)
		name_len := _wstring_length(name_propvar.val.lpwszVal)

		if id_len >= len(props.id) || name_len >= len(props.name) {
			log.error("Skipping device", device_index, "because name or ID is too long")
			continue
		}

		utf16.decode_to_utf8(props.name[:], name_propvar.val.lpwszVal[:name_len])
		utf16.decode_to_utf8(props.id[:], id[:id_len])
	}

	ok = true
	return
}

get_default_device_id :: proc() -> (device_id: Device_ID, ok: bool) {
	device: ^wasapi.IMMDevice
	id: win.LPCWSTR

	_check(_audio.device_enumerator->GetDefaultAudioEndpoint(.eRender, .eConsole, &device)) or_return
	defer device->Release()
	_check(device->GetId(&id)) or_return
	defer win.CoTaskMemFree(id)

	utf16.decode_to_utf8(device_id[:], id[:_wstring_length(id)])

	ok = true
	return
}

@private
_run_audio_session :: proc(stream: ^Stream) -> (ok: bool) {
	impl := &stream._wasapi
	format: ^wasapi.WAVEFORMATEX
	buffer_frame_count: u32
	device: ^wasapi.IMMDevice
	audio_client: ^wasapi.IAudioClient
	render_client: ^wasapi.IAudioRenderClient
	buffer: ^u8
	buffer_duration_ms: win.DWORD
	samplerate, channels: int

	defer if !ok {
		win.SetEvent(impl.thread_ready_event)
		win.SetEvent(impl.thread_done_event)
	}

	_check(_audio.device_enumerator->GetDevice(&impl.device_id[0], &device)) or_return
	defer device->Release()

	_check(device->Activate(wasapi.IAudioClient_UUID, win.CLSCTX_ALL, nil, auto_cast &audio_client)) or_return
	defer audio_client->Release()

	_check(audio_client->GetMixFormat(&format)) or_return
	defer win.CoTaskMemFree(format)

	_check(audio_client->Initialize(.SHARED, 0, 1e7, 0, format, nil)) or_return
	audio_client->GetBufferSize(&buffer_frame_count)
	_check(audio_client->GetService(wasapi.IAudioRenderClient_UUID, auto_cast &render_client)) or_return
	defer render_client->Release()
	_check(audio_client->GetService(wasapi.ISimpleAudioVolume_UUID, auto_cast &impl.volume_control)) or_return
	defer _safe_release(&impl.volume_control)

	
	render_client->GetBuffer(buffer_frame_count, &buffer)
	render_client->ReleaseBuffer(buffer_frame_count, 0)
	
	buffer_duration_ms = u32(format.nSamplesPerSec*1000) / buffer_frame_count
	
	log.debug("Buffer frames:", buffer_frame_count)
	log.debug("Buffer duration:", buffer_duration_ms, "ms")
	log.debug("Sample rate:", format.nSamplesPerSec, "Hz")

	stream.channels = auto_cast format.nChannels
	stream.samplerate = auto_cast format.nSamplesPerSec

	// We've set the stream info. Now the calling thread can continue
	win.SetEvent(impl.thread_ready_event)

	samplerate = auto_cast format.nSamplesPerSec
	channels = auto_cast format.nChannels

	audio_client->Start()
	for !impl.want_stop_thread {
		frame_padding: u32
		avail_frames: u32

		if win.WaitForSingleObject(impl.thread_interrupt_event, buffer_duration_ms/2) != win.WAIT_TIMEOUT {
			win.ResetEvent(impl.thread_interrupt_event)
			audio_client->Stop()
			audio_client->Reset()
			audio_client->Start()
		}

		if impl.want_stop_thread {break}

		audio_client->GetCurrentPadding(&frame_padding)
		avail_frames = buffer_frame_count - frame_padding

		render_client->GetBuffer(avail_frames, &buffer)
		stream._callback(stream._callback_data, (cast([^]f32)buffer)[:int(avail_frames)*channels])
		render_client->ReleaseBuffer(avail_frames, 0)
	}

	win.SetEvent(impl.thread_done_event)

	ok = true
	return
}

@private
_thread_proc :: proc(thread_data: ^thread.Thread) {
	_run_audio_session(cast(^Stream) thread_data.data)
}

