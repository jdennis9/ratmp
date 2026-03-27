package main

audio_use_null :: proc() {
	_audio_impl_init = proc(callback: Audio_Callback, callback_data: rawptr) -> bool {return true}
	_audio_impl_shutdown = proc() {}
	_audio_impl_start = proc() -> bool {return true}
	_audio_impl_drop_buffer = proc() {}
	_audio_impl_pause = proc() -> bool {return true}
	_audio_impl_resume = proc() -> bool {return true}
	_audio_impl_is_paused = proc() -> bool {return true}
	_audio_impl_stop = proc() {}
	_audio_impl_get_volume = proc() -> f32 {return 1}
	_audio_impl_set_volume = proc(v: f32) {}
}
