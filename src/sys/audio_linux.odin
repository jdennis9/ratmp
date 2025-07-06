package sys

import "base:runtime"

import "core:c"
import "core:time"
import pa "src:bindings/portaudio"

@(private="file")
_Stream_Info :: struct {
	callback_data: rawptr,
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	ctx: runtime.Context,
}

Audio_Stream :: struct {
	using common: Audio_Stream_Common,
	stream: pa.Stream,
	info: ^_Stream_Info,
}

@private
_callback_wrapper :: proc "c" (
	input, output: rawptr,
    frame_count: c.ulong,
    time_info: ^pa.StreamCallbackTimeInfo,
    status_flags: pa.StreamCallbackFlags,
    user_data: rawptr,
) -> pa.StreamCallbackResult {
	stream := cast(^_Stream_Info) user_data

	context = stream.ctx
	output_buf: []f32 = (cast([^]f32)output)[:frame_count*2]

	status := stream.stream_callback(stream.callback_data, output_buf, 2, 48000)
	if status == .Finish {
		stream.event_callback(stream.callback_data, .Finish)
	}

	return .Continue
}

audio_create_stream :: proc(
	stream_callback: Audio_Stream_Callback,
	event_callback: Audio_Event_Callback,
	callback_data: rawptr
) -> (stream: Audio_Stream, ok: bool) {
	@static initialized: bool
	if !initialized {
		if pa.Initialize() != .NoError {
			return {}, false
		}
		initialized = true
	}

	free(stream.info)
	stream.info = new(_Stream_Info)
	stream.info.callback_data = callback_data
	stream.info.stream_callback = stream_callback
	stream.info.event_callback = event_callback
	stream.info.ctx = context

	pa.OpenDefaultStream(&stream.stream, 0, 2, pa.SampleFormat_Float32, 48000, 24000, _callback_wrapper, stream.info)
	pa.StartStream(stream.stream)

	return stream, true
}

audio_drop_buffer :: proc(stream: ^Audio_Stream) {
	// @TODO
	// This can't be done with PortAudio for some reason
}

audio_pause :: proc(stream: ^Audio_Stream) {
	if stream.stream == nil {return}
	pa.StopStream(stream.stream)
}

audio_resume :: proc(stream: ^Audio_Stream) {
	if stream.stream == nil {return}
	pa.StartStream(stream.stream)
}

audio_set_volume :: proc(stream: ^Audio_Stream, volume: f32) {
}

audio_get_volume :: proc(stream: ^Audio_Stream) -> (volume: f32) {
	return 1
}

audio_get_buffer_timestamp :: proc(stream: ^Audio_Stream) -> (time.Tick, bool) {
	return {}, true
}

audio_destroy_stream :: proc(stream: ^Audio_Stream) {
	pa.CloseStream(stream.stream)
}
