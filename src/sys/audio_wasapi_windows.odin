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
package sys

import win "core:sys/windows"
import "core:thread"
import "core:log"
import "core:sync"

import "src:bindings/wasapi"

MAX_OUTPUT_CHANNELS :: 2

_WASAPI_Stream :: struct {
	using base: Audio_Stream,
	volume_controller: ^wasapi.ISimpleAudioVolume,
	ready_event: win.HANDLE,
	request_stop_event: win.HANDLE,
	request_drop_buffer_event: win.HANDLE,
	request_pause_event: win.HANDLE,
	request_resume_event: win.HANDLE,
	is_paused: bool,
	status: _Session_Status,
	callback_status: Audio_Callback_Status,
	volume: f32,
	thread: ^thread.Thread,
	lock: sync.Mutex,
}

_Session_Status :: enum {
	Ok,
	FailedToStart,
	BufferError,
}

_device_enumerator: ^wasapi.IMMDeviceEnumerator

@private
audio_use_wasapi_backend :: proc() {
	_audio_impl_init = _init
	_audio_impl_shutdown = _shutdown
	_audio_impl_create_stream = _create_stream
	_audio_impl_destroy_stream = _destroy_stream
	_audio_impl_stream_drop_buffer = _stream_drop_buffer
	_audio_impl_stream_set_volume = _stream_set_volume
	_audio_impl_stream_get_volume = _stream_get_volume
	_audio_impl_stream_pause = _stream_pause
	_audio_impl_stream_resume = _stream_resume
}

_init :: proc() -> bool {
	win32_check(
		win.CoCreateInstance(
			&wasapi.CLSID_MMDeviceEnumerator, nil, win.CLSCTX_ALL,
			wasapi.IMMDeviceEnumerator_UUID, auto_cast &_device_enumerator
		)
	) or_return

	return true
}

_shutdown :: proc() {

}

_create_stream :: proc(
	config: Audio_Stream_Config,
) -> (handle: ^Audio_Stream, ok: bool) {

	stream := new(_WASAPI_Stream)
	defer if !ok {free(stream)}

	stream.thread = thread.create(_audio_thread_proc)
	stream.thread.data = stream
	stream.thread.init_context = context
	stream.ready_event = win.CreateEventW(nil, true, false, nil)
	stream.request_stop_event = win.CreateEventW(nil, true, false, nil)
	stream.request_drop_buffer_event = win.CreateEventW(nil, true, false, nil)
	stream.request_pause_event = win.CreateEventW(nil, true, false, nil)
	stream.request_resume_event = win.CreateEventW(nil, true, false, nil)

	thread.start(stream.thread)
	win.WaitForSingleObject(stream.ready_event, win.INFINITE)
	
	return stream, stream.status == .Ok
}

_stream_drop_buffer :: proc(self: ^Audio_Stream) {
	stream := cast(^_WASAPI_Stream) self
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream.thread != nil {
		win.SetEvent(stream.request_drop_buffer_event)
	}
}

_stream_pause :: proc(self: ^Audio_Stream) {
	stream := cast(^_WASAPI_Stream) self

	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if !stream.is_paused {
		win.SetEvent(stream.request_pause_event)
	}
}

_stream_resume :: proc(self: ^Audio_Stream) {
	stream := cast(^_WASAPI_Stream) self

	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream.is_paused {
		win.SetEvent(stream.request_resume_event)
	}
}

_stream_set_volume :: proc(self: ^Audio_Stream, volume: f32) {
	stream := cast(^_WASAPI_Stream) self

	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream.volume_controller == nil {return}
	stream.volume_controller->SetMasterVolume(volume, nil)
	sync.atomic_store(&stream.volume, volume)
}

_stream_get_volume :: proc(self: ^Audio_Stream) -> (volume: f32) {
	stream := cast(^_WASAPI_Stream) self

	if stream.volume_controller == nil {return 1}
	return sync.atomic_load(&stream.volume)
}

_destroy_stream :: proc(self: ^Audio_Stream) {
	stream := cast(^_WASAPI_Stream) self

	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream.thread != nil {
		win.SetEvent(stream.request_resume_event)
		win.SetEvent(stream.request_stop_event)
		if !thread.is_done(stream.thread) {thread.join(stream.thread)}
		thread.destroy(stream.thread)
		win.CloseHandle(stream.ready_event)
		win.CloseHandle(stream.request_stop_event)
		win.CloseHandle(stream.request_drop_buffer_event)
		win.CloseHandle(stream.request_pause_event)
	}

	free(stream)
}

@(private="file")
_run_wasapi_session :: proc(stream: ^_WASAPI_Stream) -> (ok: bool) {
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
		win.SetEvent(stream.ready_event)
	}

	win32_check(_device_enumerator->GetDefaultAudioEndpoint(.eRender, .eConsole, &device)) or_return
	defer device->Release()

	win32_check(device->Activate(wasapi.IAudioClient_UUID, win.CLSCTX_ALL, nil, auto_cast &audio_client)) or_return
	defer audio_client->Release()

	win32_check(audio_client->GetMixFormat(&format)) or_return
	defer win.CoTaskMemFree(format)

	format.nChannels = min(format.nChannels, MAX_OUTPUT_CHANNELS)

	win32_check(audio_client->Initialize(.SHARED, 0, 1e7, 0, format, nil)) or_return
	audio_client->GetBufferSize(&buffer_frame_count)
	win32_check(audio_client->GetService(wasapi.IAudioRenderClient_UUID, auto_cast &render_client)) or_return
	defer render_client->Release()
	win32_check(audio_client->GetService(wasapi.ISimpleAudioVolume_UUID, auto_cast &stream.volume_controller)) or_return
	defer win32_safe_release(&stream.volume_controller)

	if stream.volume_controller != nil {
		volume: f32
		stream.volume_controller->GetMasterVolume(&volume)
		sync.atomic_store(&stream.volume, volume)
	}
	
	log.debug("Sample rate:", format.nSamplesPerSec, "Hz")
	
	stream.channels = auto_cast format.nChannels
	stream.samplerate = auto_cast format.nSamplesPerSec
	
	// We've set the stream info. Now the calling thread can continue
	win.SetEvent(stream.ready_event)

	// Fill and release first buffer right now
	render_client->GetBuffer(buffer_frame_count, &buffer)
	status = stream.config.stream_callback(
		stream.config.callback_data, (cast([^]f32)buffer)[:i32(buffer_frame_count)*stream.channels],
		stream.channels, stream.samplerate
	)
	render_client->ReleaseBuffer(buffer_frame_count, 0)
	buffer_duration_ms = u32(format.nSamplesPerSec*1000) / buffer_frame_count

	log.debug("Buffer frames:", buffer_frame_count)
	log.debug("Buffer duration:", buffer_duration_ms, "ms")

	audio_client->Start()
	for {
		frame_padding: u32
		avail_frames: u32

		wait_objects := []win.HANDLE {
			stream.request_stop_event,
			stream.request_drop_buffer_event,
			stream.request_pause_event,
		}

		if obj := win.WaitForMultipleObjects(auto_cast len(wait_objects), raw_data(wait_objects), false, buffer_duration_ms/2); obj != win.WAIT_TIMEOUT {
			if obj == win.WAIT_OBJECT_0 {
				win.ResetEvent(stream.request_stop_event)
				audio_client->Stop()

				break
			}
			else if obj == win.WAIT_OBJECT_0+1 {
				win.ResetEvent(stream.request_drop_buffer_event)
				audio_client->Stop()
				audio_client->Reset()
				stream.config.event_callback(stream.config.callback_data, .DropBuffer)
				audio_client->Start()
			}
			else if obj == win.WAIT_OBJECT_0+2 {
				win.ResetEvent(stream.request_pause_event)
				stream.is_paused = true
				audio_client->Stop()
				
				stream.config.event_callback(stream.config.callback_data, .Pause)

				win.WaitForSingleObject(stream.request_resume_event, win.INFINITE)
				stream.is_paused = false

				stream.config.event_callback(stream.config.callback_data, .Resume)
				
				win.ResetEvent(stream.request_resume_event)
				audio_client->Start()
			}
		}
		
		if status == .Finish {
			if stream.config.event_callback != nil {
				stream.config.event_callback(stream.config.callback_data, .Finish)
			}
		}
		
		audio_client->GetCurrentPadding(&frame_padding)
		avail_frames = buffer_frame_count - frame_padding
		
		if win32_check(render_client->GetBuffer(avail_frames, &buffer)) && buffer != nil {
			status = stream.config.stream_callback(
				stream.config.callback_data, (cast([^]f32)buffer)[:i32(avail_frames)*stream.channels],
				stream.channels, stream.samplerate
			)
		}
		else {
			stream.status = .BufferError
			return
		}

		if !win32_check(render_client->ReleaseBuffer(avail_frames, 0)) {
			stream.status = .BufferError
			return
		}
	}
	
	ok = true
	return
}

@(private="file")
_audio_thread_proc :: proc(thread_data: ^thread.Thread) {
	stream := cast(^_WASAPI_Stream) thread_data.data
	for {
		_run_wasapi_session(stream)
		if stream.status == .FailedToStart || stream.status == .Ok {
			return
		}
		log.debug("Restarting audio stream...")
	}
}
