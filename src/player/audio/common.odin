package audio;


_MAX_DEVICE_NAME_LEN :: 127;
Device_Name :: [_MAX_DEVICE_NAME_LEN+1]u8;
Device_Props :: struct {
	name: Device_Name,
};


Stream_Info :: struct {
	sample_rate, channels, delay_ms, buffer_duration_ms: i32,
};

//Callback :: #type proc "c" (buffer: [^]f32, frames: i32, data: rawptr);
Callback :: #type proc(buffer: []f32, data: rawptr);

