#+private file
package main

import "core:thread"
import "src:bindings/wasapi"
import win "core:sys/windows"
import "core:sync"
import "core:log"

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

_wasapi: struct {
	callback: Audio_Callback,
	callback_data: rawptr,
	volume_controller: ^wasapi.ISimpleAudioVolume,
	session_thread: ^thread.Thread,
	status: _Session_Status,
	device_enumerator: ^wasapi.IMMDeviceEnumerator,
	spec: Audio_Spec,
	volume: f32,
	is_paused: b32,
	in_events: [IN_EVENT__COUNT]win.HANDLE,
	out_events: [OUT_EVENT__COUNT]win.HANDLE,
}

_send_event :: proc(ev: int) {win.SetEvent(_wasapi.in_events[ev])}
_wait_event :: proc(ev: int) {win.WaitForSingleObject(_wasapi.out_events[ev], win.INFINITE)}

@private
use_audio_wasapi :: proc() {
	_audio_impl_init = proc(cb: Audio_Callback, cb_data: rawptr) -> bool {
		win32_check(
			win.CoCreateInstance(
				&wasapi.CLSID_MMDeviceEnumerator, nil, win.CLSCTX_ALL,
				wasapi.IMMDeviceEnumerator_UUID, auto_cast &_wasapi.device_enumerator
			)
		) or_return
		
		for &ev in _wasapi.in_events do ev = win.CreateEventW(nil, false, false, nil)
		for &ev in _wasapi.out_events do ev = win.CreateEventW(nil, false, false, nil)

		_wasapi.callback = cb
		_wasapi.callback_data = cb_data

		return true
	}

	_audio_impl_shutdown = proc() {
		_audio_impl_stop()
		win32_safe_release(&_wasapi.device_enumerator)
		for ev in _wasapi.in_events do win.CloseHandle(ev)
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

		_send_event(IN_EVENT_KILL)
		_wait_event(OUT_EVENT_STOPPED)
		thread.join(w.session_thread)
		thread.destroy(w.session_thread)

		w.session_thread = nil
	}

	_audio_impl_drop_buffer = proc() {
		w := &_wasapi
		_send_event(IN_EVENT_DROP_BUFFER)
	}

	_audio_impl_pause = proc() -> bool {
		w := &_wasapi
		if !w.is_paused {
			_send_event(IN_EVENT_PAUSE)
			return true
		}
		return false
	}

	_audio_impl_resume = proc() -> bool {
		w := &_wasapi
		if w.is_paused {
			_send_event(IN_EVENT_RESUME)
			return true
		}
		return false
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
	format: ^wasapi.WAVEFORMATEX
	buffer_frame_count: u32
	device: ^wasapi.IMMDevice
	audio_client: ^wasapi.IAudioClient
	render_client: ^wasapi.IAudioRenderClient
	buffer: ^u8
	buffer_duration_ms: win.DWORD
	status := Audio_Callback_Status.Continue

	win.CoInitializeEx()

	defer if !ok {
		win.SetEvent(w.out_events[OUT_EVENT_READY])
	}

	win32_check(w.device_enumerator->GetDefaultAudioEndpoint(.eRender, .eConsole, &device)) or_return
	defer device->Release()

	win32_check(device->Activate(wasapi.IAudioClient_UUID, win.CLSCTX_ALL, nil, auto_cast &audio_client)) or_return
	defer audio_client->Release()

	win32_check(audio_client->GetMixFormat(&format)) or_return
	defer win.CoTaskMemFree(format)

	format.nChannels = min(format.nChannels, 2)

	win32_check(audio_client->Initialize(.SHARED, 0, 1e7, 0, format, nil)) or_return
	audio_client->GetBufferSize(&buffer_frame_count)
	win32_check(audio_client->GetService(wasapi.IAudioRenderClient_UUID, auto_cast &render_client)) or_return
	defer render_client->Release()
	win32_check(audio_client->GetService(wasapi.ISimpleAudioVolume_UUID, auto_cast &w.volume_controller)) or_return
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
	for {
		frame_padding: u32
		avail_frames: u32

		if obj := win.WaitForMultipleObjects(IN_EVENT__COUNT, raw_data(&w.in_events), false, buffer_duration_ms/2); obj != win.WAIT_TIMEOUT {
			if obj == win.WAIT_OBJECT_0 + IN_EVENT_KILL {
				audio_client->Stop()

				break
			}
			else if obj == win.WAIT_OBJECT_0 + IN_EVENT_DROP_BUFFER {
				audio_client->Stop()
				audio_client->Reset()
				w.callback(w.callback_data, .BufferDropped, nil, {})
				audio_client->Start()
			}
			else if obj == win.WAIT_OBJECT_0 + IN_EVENT_PAUSE {
				w.is_paused = true
				audio_client->Stop()
				
				w.callback(w.callback_data, .Paused, nil, {})

				win.WaitForSingleObject(w.in_events[IN_EVENT_RESUME], win.INFINITE)
				w.is_paused = false

				w.callback(w.callback_data, .Resumed, nil, {})
				
				audio_client->Start()
			}
		}
		
		if status == .Finish {
			w.callback(w.callback_data, .TrackFinised, nil, {})
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
		_reset_events(w.in_events[:])
		_reset_events(w.out_events[:])
		if w.status == .FailedToStart || w.status == .Ok {
			return
		}
		log.debug("Restarting audio stream...")
	}
}

