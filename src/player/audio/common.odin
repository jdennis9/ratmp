package audio

Device_ID :: [128]u8

Device_Props :: struct {
	id: Device_ID,
	name: [128]u8,
}

@private
_Stream_Common :: struct {
	samplerate, channels: int,
	_callback: Callback,
	_callback_data: rawptr,
}

Callback :: #type proc(data: rawptr, buffer: []f32)

