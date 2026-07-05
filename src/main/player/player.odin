package player

import "core:testing"
import "src:main/shared"
import "src:dsp"
import lib "src:main/library"

Config :: struct {
	no_audio: bool,
}

Player :: struct {
	queue:                      [dynamic]lib.Track_ID,
	queue_pos:                  int,
	queue_is_shuffled:          bool,
	playback_thread:            Playback_Thread,
	output_rings:               [AUDIO_MAX_CHANNELS]Ring_Buffer(f32),
	output_intermediate_buffer: [AUDIO_MAX_CHANNELS][dynamic]f32,
}

@(private="file")
_player: Player

@(private="file")
_audio_callback :: proc(
	_:     rawptr,
	event: Audio_Callback_Event,
	data:  []f32,
	spec:  Audio_Spec
) -> Audio_Callback_Status {
	p := &_player

	switch event {
	case .Stream:
		output_buf: [AUDIO_MAX_CHANNELS][]f32
		frame_count := len(data) / spec.channels
		
		for ch in 0..<spec.channels {
			resize(&p.output_intermediate_buffer[ch], frame_count)
			output_buf[ch] = p.output_intermediate_buffer[ch][:]
		}
		
		status := playback_thread_request_frames(&p.playback_thread, output_buf[:spec.channels], spec.samplerate)

		if status == .Eof do return .Finish

		dsp.interlace(output_buf[:spec.channels], data)

		for ch in 0..<spec.channels {
			shared.rb_produce(&p.output_rings[ch], output_buf[ch])
		}

	case .BufferDropped:
	case .Paused:
	case .Resumed:
	case .TrackFinished:
	}

	return .Continue
}

init :: proc(cfg: Config) -> bool {
	p := &_player

	if !cfg.no_audio {
		when ODIN_OS == .Windows do audio_use_wasapi()
		else when ODIN_OS == .Linux do audio_use_pulse()
	}
	else {
		audio_use_null()
	}

	audio_init(_audio_callback, nil) or_return
	audio_start() or_return

	playback_thread_init(&p.playback_thread, context.allocator)

	return true
}

shutdown :: proc() {
	p := &_player
	delete(p.queue)

	playback_thread_destroy(&p.playback_thread)
	audio_shutdown()

	_player = {}
}
