package server

import "base:runtime"
import "core:sync"
import "core:slice"
import "core:math/rand"
import "core:time"
import "core:log"
import "core:path/filepath"
import "core:math"

import decoder "src:decoder_v2"
import "src:util"

MAX_OUTPUT_CHANNELS :: 2

Server :: struct {
	ctx: runtime.Context,

	library: Library,
	stream: Audio_Stream,

	playback_lock: sync.Mutex,
	decoder: decoder.Decoder,
	current_track_id: Track_ID,
	current_playlist_id: Playlist_ID,
	queue: [dynamic]Track_ID,
	queue_pos: int,
	paused: bool,
	enable_shuffle: bool,
	queue_is_shuffled: bool,

	output_copy: struct {
		timestamp: time.Tick,
		channels, samplerate: int,
		// The second number for the struct dictates how many samples can
		// be retrieved for analysis windows. N means (N*(samplerate/2)) samples can
		// be used at a time
		buffers: [MAX_OUTPUT_CHANNELS]util.Rotating_Buffer(f32, 3),
	},

	paths: struct {
		playlists_folder: string,
		state: string,
		library: string,
	},

	event_handlers: [dynamic]Event_Handler,
	event_queue: [dynamic]Event,
	wake_proc: proc(), // Called whenever an event is sent
}

init :: proc(state: ^Server, wake_proc: proc(), data_dir: string, config_dir: string) -> (ok: bool) {
	log.debug("Initializing server...")
	state.ctx = context
	state.wake_proc = wake_proc

	state.paths.playlists_folder = filepath.join({data_dir, "Playlists"})
	state.paths.state = filepath.join({config_dir, "state.json"})
	state.paths.library = filepath.join({data_dir, "library.sqlite"})

	library_init(&state.library, state.paths.playlists_folder) or_return
	state.stream = audio_create_stream(_audio_stream_callback, _audio_event_callback, state) or_return
	set_paused(state, true)

	library_load_from_file(&state.library, state.paths.library)
	library_scan_playlists(&state.library)

	ok = true
	return
}

clean_up :: proc(state: ^Server) {
	library_save_to_file(state.library, state.paths.library)
	library_destroy(&state.library)
	audio_destroy_stream(&state.stream)
}

play_track :: proc(state: ^Server, filename: string, track_id: Track_ID, dont_drop_buffer := false) -> bool {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	if !dont_drop_buffer {audio_drop_buffer(&state.stream)}
	decoder.open(&state.decoder, filename) or_return
	state.current_track_id = track_id
	set_paused(state, false, no_lock=true)

	send_event(state, Current_Track_Changed_Event{track_id = track_id})

	return true
}

seek_to_second :: proc(state: ^Server, second: int) {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	decoder.seek(&state.decoder, second)
	audio_drop_buffer(&state.stream)
}

get_track_duration_seconds :: proc(state: ^Server) -> int {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	return decoder.get_duration(state.decoder)
}

get_track_second :: proc(state: ^Server) -> int {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	return decoder.get_second(state.decoder)
}

set_paused :: proc(state: ^Server, paused: bool, no_lock := false) {
	if state.paused != paused {
		state.paused = paused
		if paused {
			audio_pause(&state.stream)
		}
		else {
			audio_resume(&state.stream)
		}
		
		send_event(state, State_Changed_Event{paused = state.paused})
	}
}

is_paused :: proc(state: Server) -> bool {return state.paused}

set_volume :: proc(state: ^Server, volume: f32) {
	audio_set_volume(&state.stream, volume)
}

get_volume :: proc(state: ^Server) -> f32 {
	return audio_get_volume(&state.stream)
}

play_playlist :: proc(
	state: ^Server,
	tracks: []Track_ID, playlist_id: Playlist_ID,
	first_track: Track_ID = 0
) {
	play_index := 0
	
	state.current_playlist_id = playlist_id

	resize(&state.queue, len(tracks))
	copy(state.queue[:], tracks)

	if state.enable_shuffle {
		rand.shuffle(state.queue[:])
		state.queue_is_shuffled = true
	}
	else {
		state.queue_is_shuffled = false
	}

	if first_track != 0 {
		play_index = slice.linear_search(state.queue[:], first_track) or_else 0
	}

	set_queue_position(state, play_index)
}

set_shuffle_enabled :: proc(state: ^Server, enabled: bool) {
	if enabled && !state.queue_is_shuffled && len(state.queue) > 1 {
		rand.shuffle(state.queue[:])
		state.queue_is_shuffled = true
	}
	state.enable_shuffle = enabled
}

play_prev_track :: proc(state: ^Server, dont_drop_buffer := false) {
	set_queue_position(state, state.queue_pos-1, dont_drop_buffer)
}

play_next_track :: proc(state: ^Server, dont_drop_buffer := false) {
	set_queue_position(state, state.queue_pos+1, dont_drop_buffer)
}

set_queue_position :: proc(state: ^Server, pos: int, dont_drop_buffer := false) {
	if len(state.queue) == 0 {return}
	state.queue_pos = pos

	if state.queue_pos >= len(state.queue) {
		state.queue_pos = 0
	}
	else if state.queue_pos < 0 {
		state.queue_pos = 0
	}

	path_buf: [512]u8
	track_id := state.queue[state.queue_pos]
	if path, found := library_get_track_path(state.library, path_buf[:], track_id); found {
		play_track(state, path, track_id, dont_drop_buffer)
	}
}

Audio_Time_Frame :: struct {
	samplerate, channels: int,
	data: [MAX_OUTPUT_CHANNELS][]f32,
}

audio_time_frame_from_playback :: proc(
	state: ^Server, output: [][$WINDOW_SIZE]f32,
	from_timestamp: time.Tick
) -> (samplerate, channels: int, ok: bool) {
	time_frame := f32(WINDOW_SIZE)/f32(state.stream.samplerate)
	assert(time_frame > 0)

	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	cpy := state.output_copy
	if cpy.channels == 0 || len(cpy.buffers[0].data) == 0 {return}

	time_start := cast(f32) time.duration_seconds(time.tick_diff(cpy.timestamp, from_timestamp))
	time_end := time_start + time_frame

	//assert(time_start >= 0)
	if time_start < 0 {return}

	start_frame := int(time_start * f32(cpy.samplerate))
	end_frame := int(time_end * f32(cpy.samplerate))

	start_frame = clamp(start_frame, 0, len(cpy.buffers[0].data)-1)
	end_frame = clamp(end_frame, 0, len(cpy.buffers[0].data)-1)

	assert(start_frame <= end_frame)
	if start_frame >= end_frame {return}

	//frame_count := (end_frame - start_frame) + 1

	channels = cpy.channels
	samplerate = cpy.samplerate
	for ch in 0..<cpy.channels {
		//output.data[ch] = make([]f32, want_frame_count, allocator)
		copy(output[ch][:], cpy.buffers[ch].data[start_frame:end_frame])
	}

	ok = true
	return
}

import "core:fmt"

audio_time_frame_delete :: proc(time_frame: Audio_Time_Frame) {
	for d in time_frame.data {
		delete(d)
	}
}

@(private="file")
_update_output_copy_buffers :: proc(state: ^Server, input: []f32, channels, samplerate: int) {
	cpy := &state.output_copy
	
	if cpy.channels != channels || cpy.samplerate != samplerate {
		_clear_output_copy_buffer(state)
	}

	cpy.channels = channels
	cpy.samplerate = samplerate

	cpy.timestamp = time.tick_now()

	channel_data: [MAX_OUTPUT_CHANNELS][dynamic]f32
	defer {
		for ch in 0..<channels {
			delete(channel_data[ch])
		}
	}

	//first_buffer_length := cpy.buffers[0].sizes[0]

	_deinterlace(input, channels, &channel_data)
	for ch in 0..<channels {
		util.rotating_buffer_push(&cpy.buffers[ch], channel_data[ch][:])
	}

	cpy.timestamp._nsec -= auto_cast((f32(cpy.buffers[0].sizes[2]) / f32(samplerate)) * 1e9)
	//cpy.timestamp._nsec -= auto_cast((f32(first_buffer_length) / f32(samplerate)) * 1e9)
}

@(private="file")
_clear_output_copy_buffer :: proc(state: ^Server) {
	log.debug("Floob")
	for &b in state.output_copy.buffers {
		util.rotating_buffer_reset(&b)
	}
}

@(private="file")
_audio_stream_callback :: proc(data: rawptr, buffer: []f32, channels, samplerate: i32) -> Audio_Callback_Status {
	state := cast(^Server)data

	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	for &f in buffer {f = 0}

	if !state.paused && decoder.is_open(state.decoder) {
		status := decoder.fill_buffer(&state.decoder, buffer, int(channels), int(samplerate))

		_update_output_copy_buffers(state, buffer, int(channels), int(samplerate))

		if status == .Eof {return .Finish}
		return .Continue
	}

	return .Continue
}

@(private="file")
_audio_event_callback :: proc(data: rawptr, event: Audio_Event) {
	state := cast(^Server)data

	#partial switch event {
		case .DropBuffer: {
			sync.lock(&state.playback_lock)
			defer sync.unlock(&state.playback_lock)
			_clear_output_copy_buffer(state)
		}

		case .Finish: {
			play_next_track(state, true)
		}
	}
}

@(private="file")
_deinterlace :: proc(input: []f32, channels: int, out: ^[MAX_OUTPUT_CHANNELS][dynamic]f32) {
	for ch in 0..<channels {
		resize(&out[ch], len(input)/channels)
	}

	sample_count := len(input)
	sample: int
	frame: int

	for sample < sample_count {
		for ch in 0..<channels {
			out[ch][frame] = input[sample + ch]
		}

		sample += channels
		frame += 1
	}
}
