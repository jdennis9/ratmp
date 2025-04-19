package audio;

Device_ID :: [128]u8;

Device_Props :: struct {
	id: Device_ID,
	name: [128]u8,
};

Stream_Info :: struct {
	sample_rate, channels: i32,
};

Callback :: #type proc(buffer: []f32, data: rawptr);

