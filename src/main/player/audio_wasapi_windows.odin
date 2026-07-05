/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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
#+private file
package player

import "src:main/shared"
import "core:time"
import "core:thread"
import "vendor:windows/wasapi"
import win "core:sys/windows"
import "core:sync"
import "core:log"

win32_check :: shared.win32_check
win32_safe_release :: shared.win32_safe_release

IID_ISimpleAudioVolume := &win.IID{0x87CE5498, 0x68D6, 0x44E5, {0x92, 0x15, 0x6D, 0xA4, 0x7E, 0xF8, 0x83, 0xD8}}
ISimpleAudioVolume_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	SetMasterVolume: proc "system" (this: ^ISimpleAudioVolume, fLevel: f32, EventContext: win.LPCGUID) -> win.HRESULT,
	GetMasterVolume: proc "system" (this: ^ISimpleAudioVolume, pfLevel: ^f32) -> win.HRESULT,
	SetMute: proc "system" (this: ^ISimpleAudioVolume, bMute: win.BOOL, EventContext: win.LPCGUID) -> win.HRESULT,
	GetMute: proc "system" (this: ^ISimpleAudioVolume, pbMute: ^win.BOOL) -> win.HRESULT,
}

ISimpleAudioVolume :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vtable: ^ISimpleAudioVolume_VTable,
}

_Session_Status :: enum {
	Ok,
	FailedToStart,
	BufferError,
}

IN_EVENT_DROP_BUFFER :: 0
IN_EVENT_PAUSE :: 1
IN_EVENT_RESUME :: 2
IN_EVENT_KILL :: 3
IN_EVENT__COUNT :: 4

OUT_EVENT_READY :: 0
OUT_EVENT_STOPPED :: 1
OUT_EVENT__COUNT :: 2

_In_Event :: enum {
	Pause,
	Resume,
	DropBuffer,
	Kill,
}

_wasapi: struct {
	callback:          Audio_Callback,
	callback_data:     rawptr,
	volume_controller: ^ISimpleAudioVolume,
	session_thread:    ^thread.Thread,
	status:            _Session_Status,
	device_enumerator: ^wasapi.IMMDeviceEnumerator,
	spec:              Audio_Spec,
	volume:            f32,
	is_paused:         b32,
	in_events:         [_In_Event]int,
	interrupt_event:   win.HANDLE,
	out_events:        [OUT_EVENT__COUNT]win.HANDLE,
	event_semaphore:   sync.Sema,
}

_send_event :: proc(ev: _In_Event) {
	_wasapi.in_events[ev] += 1
	sync.sema_post(&_wasapi.event_semaphore)
}
_wait_event :: proc(ev: int) {win.WaitForSingleObject(_wasapi.out_events[ev], win.INFINITE)}

@private
audio_use_wasapi :: proc() {
	_audio_impl_init = proc(cb: Audio_Callback, cb_data: rawptr) -> bool {
		win.CoInitializeEx()

		win32_check(
			win.CoCreateInstance(
				wasapi.CLSID_MMDeviceEnumerator, nil, win.CLSCTX_ALL,
				wasapi.IID_IMMDeviceEnumerator, auto_cast &_wasapi.device_enumerator
			)
		) or_return
		
		for &ev in _wasapi.out_events do ev = win.CreateEventW(nil, false, false, nil)

		_wasapi.callback = cb
		_wasapi.callback_data = cb_data

		return true
	}

	_audio_impl_shutdown = proc() {
		_audio_impl_stop()
		win32_safe_release(&_wasapi.device_enumerator)
		for ev in _wasapi.out_events do win.CloseHandle(ev)
	}

	_audio_impl_start = proc() -> (ok: bool) {
		w := &_wasapi
		w.session_thread = thread.create(_audio_thread_proc)
		w.session_thread.init_context = context

		defer if !ok {
			thread.destroy(w.session_thread)
			w.session_thread = nil
		}
		
		thread.start(w.session_thread)
		win.WaitForSingleObject(w.out_events[OUT_EVENT_READY], win.INFINITE)

		return w.status == .Ok
	}

	_audio_impl_stop = proc() {
		w := &_wasapi
		if w.session_thread == nil do return

		_send_event(.Kill)
		_wait_event(OUT_EVENT_STOPPED)
		thread.join(w.session_thread)
		thread.destroy(w.session_thread)

		w.session_thread = nil
		w.in_events = {}
	}

	_audio_impl_drop_buffer = proc() {
		_send_event(.DropBuffer)
	}

	_audio_impl_pause = proc() -> bool {
		w := &_wasapi
		if !w.is_paused {
			_send_event(.Pause)
			return true
		}
		return false
	}

	_audio_impl_resume = proc() -> bool {
		w := &_wasapi
		if w.is_paused {
			//_send_event(IN_EVENT_RESUME)
			_send_event(.Resume)
			return true
		}
		return false
	}

	_audio_impl_is_paused = proc() -> bool {
		return auto_cast _wasapi.is_paused
	}

	_audio_impl_get_volume = proc() -> f32 {
		return _wasapi.volume
	}

	_audio_impl_set_volume = proc(v: f32) {
		w := &_wasapi
		if w.volume_controller != nil {
			w.volume_controller->SetMasterVolume(v, nil)
			w.volume = v
		}
	}
}

_reset_events :: proc(e: []win.HANDLE) {
	for ev in e do win.ResetEvent(ev)
}

_run_session :: proc() -> (ok: bool) {
	w := &_wasapi
	format:             ^wasapi.WAVEFORMATEX
	buffer_frame_count: u32
	device:             ^wasapi.IMMDevice
	audio_client:       ^wasapi.IAudioClient
	render_client:      ^wasapi.IAudioRenderClient
	buffer:             [^]u8
	buffer_duration_ms: win.DWORD
	status := Audio_Callback_Status.Continue

	win.CoInitializeEx()

	defer if !ok {
		win.SetEvent(w.out_events[OUT_EVENT_READY])
	}

	win32_check(w.device_enumerator->GetDefaultAudioEndpoint(.Render, .Console, &device)) or_return
	defer device->Release()

	win32_check(device->Activate(wasapi.IID_IAudioClient, win.CLSCTX_ALL, nil, auto_cast &audio_client)) or_return
	defer audio_client->Release()

	win32_check(audio_client->GetMixFormat(&format)) or_return
	defer win.CoTaskMemFree(format)

	format.nChannels = min(format.nChannels, 2)

	win32_check(audio_client->Initialize(.SHARED, 0, 1e7, 0, format, nil)) or_return
	audio_client->GetBufferSize(&buffer_frame_count)
	win32_check(audio_client->GetService(wasapi.IID_IAudioRenderClient, auto_cast &render_client)) or_return
	defer render_client->Release()
	win32_check(audio_client->GetService(IID_ISimpleAudioVolume, auto_cast &w.volume_controller)) or_return
	defer win32_safe_release(&w.volume_controller)

	if w.volume_controller != nil {
		volume: f32
		w.volume_controller->GetMasterVolume(&volume)
		sync.atomic_store(&w.volume, volume)
	}
	
	log.debug("Sample rate:", format.nSamplesPerSec, "Hz")
	
	w.spec.channels = auto_cast format.nChannels
	w.spec.samplerate = auto_cast format.nSamplesPerSec
	
	// We've set the stream info. Now the calling thread can continue
	win.SetEvent(w.out_events[OUT_EVENT_READY])

	// Fill and release first buffer right now
	render_client->GetBuffer(buffer_frame_count, &buffer)
	status = w.callback(
		w.callback_data, .Stream, (cast([^]f32)buffer)[:i32(buffer_frame_count) * auto_cast w.spec.channels],
		w.spec
	)
	render_client->ReleaseBuffer(buffer_frame_count, 0)
	buffer_duration_ms = u32(format.nSamplesPerSec*1000) / buffer_frame_count

	log.debug("Buffer frames:", buffer_frame_count)
	log.debug("Buffer duration:", buffer_duration_ms, "ms")

	audio_client->Start()

	main_loop: for {
		frame_padding: u32
		avail_frames: u32

		// -----------------------------------------------------------------------
		// Wait for event or timeout
		// -----------------------------------------------------------------------
		sync.sema_wait_with_timeout(&w.event_semaphore, time.Millisecond * auto_cast(buffer_duration_ms/2))

		// -----------------------------------------------------------------------
		// Handle events
		// -----------------------------------------------------------------------
		if w.in_events[.Kill] > 0 {
			break main_loop
		}
		
		if w.in_events[.DropBuffer] > 0 {
			audio_client->Stop()
			audio_client->Reset()
			w.callback(w.callback_data, .BufferDropped, nil, {})
			audio_client->Start()
			w.in_events[.DropBuffer] -= 1
		}

		if w.in_events[.Pause] > 0 {
			w.is_paused = true
			audio_client->Stop()
			sync.sema_wait(&w.event_semaphore)
			w.is_paused = false
			audio_client->Start()
			w.in_events[.Pause] = 0
			w.in_events[.Resume] = 0
		}
		
		// -----------------------------------------------------------------------
		// Callbacks
		// -----------------------------------------------------------------------
		if status == .Finish {
			w.callback(w.callback_data, .TrackFinished, nil, {})
		}
		
		audio_client->GetCurrentPadding(&frame_padding)
		avail_frames = buffer_frame_count - frame_padding
		
		if win32_check(render_client->GetBuffer(avail_frames, &buffer)) && buffer != nil {
			status = w.callback(
				w.callback_data, .Stream, (cast([^]f32)buffer)[:avail_frames * auto_cast w.spec.channels],
				w.spec
			)
		}
		else {
			w.status = .BufferError
			return
		}

		if !win32_check(render_client->ReleaseBuffer(avail_frames, 0)) {
			w.status = .BufferError
			return
		}
	}
	
	win.SetEvent(w.out_events[OUT_EVENT_STOPPED])

	ok = true
	return
}

_audio_thread_proc :: proc(thread_data: ^thread.Thread) {
	w := &_wasapi

	for {
		_run_session()
		_reset_events(w.out_events[:])
		if w.status == .FailedToStart || w.status == .Ok {
			return
		}
		log.debug("Restarting audio stream...")
	}
}

