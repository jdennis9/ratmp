/*
    RAT MP - A cross-platform, extensible music player
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
package sys

import win "core:sys/windows"
import "core:thread"
import "core:log"
import "core:sync"
import "core:time"
//import "core:fmt"

import "src:bindings/wasapi"

MAX_OUTPUT_CHANNELS :: 2

@(private="file")
_WASAPI_Stream :: struct {
	channels, samplerate: i32,
	volume_controller: ^wasapi.ISimpleAudioVolume,
	ready_event: win.HANDLE,
	request_stop_event: win.HANDLE,
	request_drop_buffer_event: win.HANDLE,
	request_pause_event: win.HANDLE,
	request_resume_event: win.HANDLE,
	is_paused: bool,
	status: _Session_Status,
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	callback_data: rawptr,
	callback_status: Audio_Callback_Status,
	buffer_timestamp: time.Tick,
	volume: f32,
}

Audio_Stream :: struct {
	using common: Audio_Stream_Common,
	thread: ^thread.Thread,
	lock: sync.Mutex,
	_wasapi: ^_WASAPI_Stream,
}

_Session_Status :: enum {
	Ok,
	FailedToStart,
	BufferError,
}

@(private="file")
_device_enumerator: ^wasapi.IMMDeviceEnumerator

audio_create_stream :: proc(
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	callback_data: rawptr
) -> (stream: Audio_Stream, ok: bool) {
	if _device_enumerator == nil {
		win32_check(
			win.CoCreateInstance(
				&wasapi.CLSID_MMDeviceEnumerator, nil, win.CLSCTX_ALL,
				wasapi.IMMDeviceEnumerator_UUID, auto_cast &_device_enumerator
			)
		) or_return
	}

	stream._wasapi = new(_WASAPI_Stream)
	defer if !ok {free(stream._wasapi)}
	stream.thread = thread.create(_audio_thread_proc)
	stream.thread.data = stream._wasapi
	stream.thread.init_context = context
	stream._wasapi.ready_event = win.CreateEventW(nil, true, false, nil)
	stream._wasapi.request_stop_event = win.CreateEventW(nil, true, false, nil)
	stream._wasapi.request_drop_buffer_event = win.CreateEventW(nil, true, false, nil)
	stream._wasapi.request_pause_event = win.CreateEventW(nil, true, false, nil)
	stream._wasapi.request_resume_event = win.CreateEventW(nil, true, false, nil)
	stream._wasapi.stream_callback = stream_callback
	stream._wasapi.event_callback = event_callback
	stream._wasapi.callback_data = callback_data

	thread.start(stream.thread)
	win.WaitForSingleObject(stream._wasapi.ready_event, win.INFINITE)

	stream.channels = stream._wasapi.channels
	stream.samplerate = stream._wasapi.samplerate
	
	if stream._wasapi.status == .Ok {
		ok = true
		return
	}

	return {}, false
}

audio_drop_buffer :: proc(stream: ^Audio_Stream) {
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream.thread != nil && stream._wasapi != nil {
		win.SetEvent(stream._wasapi.request_drop_buffer_event)
	}
}

audio_pause :: proc(stream: ^Audio_Stream) {
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream._wasapi == nil {return}

	if !stream._wasapi.is_paused {
		win.SetEvent(stream._wasapi.request_pause_event)
	}
}

audio_resume :: proc(stream: ^Audio_Stream) {
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream._wasapi == nil {return}

	if stream._wasapi.is_paused {
		win.SetEvent(stream._wasapi.request_resume_event)
	}
}

audio_set_volume :: proc(stream: ^Audio_Stream, volume: f32) {
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream._wasapi == nil || stream._wasapi.volume_controller == nil {return}
	stream._wasapi.volume_controller->SetMasterVolume(volume, nil)
	sync.atomic_store(&stream._wasapi.volume, volume)
}

audio_get_volume :: proc(stream: ^Audio_Stream) -> (volume: f32) {
	if stream._wasapi == nil || stream._wasapi.volume_controller == nil {return 0}
	return sync.atomic_load(&stream._wasapi.volume)
}

audio_get_buffer_timestamp :: proc(stream: ^Audio_Stream) -> (time.Tick, bool) {
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream._wasapi == nil {return {}, false}
	return stream._wasapi.buffer_timestamp, true
}

audio_destroy_stream :: proc(stream: ^Audio_Stream) {
	sync.lock(&stream.lock)
	defer sync.unlock(&stream.lock)

	if stream.thread != nil && stream._wasapi != nil {
		win.SetEvent(stream._wasapi.request_resume_event)
		win.SetEvent(stream._wasapi.request_stop_event)
		if !thread.is_done(stream.thread) {thread.join(stream.thread)}
		thread.destroy(stream.thread)
		win.CloseHandle(stream._wasapi.ready_event)
		win.CloseHandle(stream._wasapi.request_stop_event)
		win.CloseHandle(stream._wasapi.request_drop_buffer_event)
		win.CloseHandle(stream._wasapi.request_pause_event)
		free(stream._wasapi)
	}
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
	status = stream.stream_callback(
		stream.callback_data, (cast([^]f32)buffer)[:i32(buffer_frame_count)*stream.channels],
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
				stream.event_callback(stream.callback_data, .DropBuffer)
				audio_client->Stop()
				audio_client->Reset()
				audio_client->Start()
				
			}
			else if obj == win.WAIT_OBJECT_0+2 {
				win.ResetEvent(stream.request_pause_event)
				stream.is_paused = true
				audio_client->Stop()
				
				stream.event_callback(stream.callback_data, .Pause)

				win.WaitForSingleObject(stream.request_resume_event, win.INFINITE)
				stream.is_paused = false

				stream.event_callback(stream.callback_data, .Resume)
				
				win.ResetEvent(stream.request_resume_event)
				audio_client->Start()
			}
		}
		
		if status == .Finish {
			// Wait for buffer to finish before we call the event callback
			win.Sleep(buffer_duration_ms/2)
			stream.event_callback(stream.callback_data, .Finish)
		}
		
		audio_client->GetCurrentPadding(&frame_padding)
		avail_frames = buffer_frame_count - frame_padding
		
		if win32_check(render_client->GetBuffer(avail_frames, &buffer)) {
			status = stream.stream_callback(
				stream.callback_data, (cast([^]f32)buffer)[:i32(avail_frames)*stream.channels],
				stream.channels, stream.samplerate
			)
			stream.buffer_timestamp = time.tick_now()
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
		ok := _run_wasapi_session(stream)
		if stream.status == .FailedToStart || stream.status == .Ok {
			return
		}
		log.debug("Restarting audio stream...")
	}
}
