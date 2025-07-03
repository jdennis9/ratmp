package sys

Audio_Event :: enum {
	Pause,
	Resume,
	DropBuffer,
	Finish,
}

Audio_Callback_Status :: enum {
	Continue,
	Finish,
}

Audio_Event_Callback :: #type proc(data: rawptr, event: Audio_Event)
Audio_Stream_Callback :: #type proc(data: rawptr, buffer: []f32, channels, samplerate: i32) -> Audio_Callback_Status

Audio_Stream_Common :: struct {
	channels, samplerate: i32,
}
