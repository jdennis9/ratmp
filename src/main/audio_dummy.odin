package main

use_audio_dummy :: proc() {
	_audio_impl_init = proc(cb: Audio_Callback, cb_data: rawptr) -> bool {return true}
	_audio_impl_shutdown = proc() {}
	_audio_impl_start = proc() -> bool {return true}
	_audio_impl_stop = proc() {}
	_audio_impl_drop_buffer = proc() {}
	_audio_impl_get_volume = proc() -> f32 {return 1}
	_audio_impl_set_volume = proc(v: f32) {}
}
