#+private
package sys

_audio_impl_init: proc() -> bool
_audio_impl_shutdown: proc()

_audio_impl_create_stream: proc(config: Audio_Stream_Config) -> (^Audio_Stream, bool)
_audio_impl_destroy_stream: proc(stream: ^Audio_Stream)

_audio_impl_stream_set_volume: proc(stream: ^Audio_Stream, volume: f32)
_audio_impl_stream_get_volume: proc(stream: ^Audio_Stream) -> f32
_audio_impl_stream_drop_buffer: proc(stream: ^Audio_Stream)
_audio_impl_stream_pause: proc(stream: ^Audio_Stream)
_audio_impl_stream_resume: proc(stream: ^Audio_Stream)
