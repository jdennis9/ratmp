package server

import "base:runtime"
import "core:sync"
import "core:slice"
import "core:math/rand"
import "core:time"
import "core:log"
import "core:path/filepath"
import "core:math"
import "core:encoding/json"
import "core:os/os2"

import decoder "src:decoder_v2"
import "src:util"
import "src:sys"

MAX_OUTPUT_CHANNELS :: 2

Playback_Mode :: enum {
	Playlist,
	RepeatPlaylist,
	RepeatSingle,
}

@private
_Saved_State :: struct {
	enable_shuffle: bool,
	playback_mode: Playback_Mode,
}

Track_Info :: decoder.File_Info

Server :: struct {
	ctx: runtime.Context,

	library: Library,
	stream: sys.Audio_Stream,

	playback_lock: sync.Mutex,
	decoder: decoder.Decoder,
	current_track_id: Track_ID,
	current_track_info: Track_Info,
	current_playlist_id: Playlist_ID,
	queue: [dynamic]Track_ID,
	queue_pos: int,
	queue_serial: uint,
	paused: bool,
	playback_mode: Playback_Mode,
	queue_is_shuffled: bool,
	enable_shuffle: bool,

	output_copy: struct {
		channels, samplerate: int,
		prev_buffer: [dynamic]f32,
		buffers: [MAX_OUTPUT_CHANNELS]util.Ring_Buffer(f32, 64<<10),
	},

	paths: struct {
		playlists_folder: string,
		state: string,
		library: string,
	},

	event_handlers: [dynamic]Event_Handler,
	event_queue: [dynamic]Event,
	wake_proc: proc(), // Called whenever an event is sent

	background_scan: _Background_Scan,
	scan_queue: [dynamic]Path,
	library_save_serial: uint,

	saved_state: _Saved_State,
}

init :: proc(state: ^Server, wake_proc: proc(), data_dir: string, config_dir: string) -> (ok: bool) {
	log.debug("Initializing server...")
	state.ctx = context
	state.wake_proc = wake_proc

	state.paths.playlists_folder = filepath.join({data_dir, "Playlists"})
	state.paths.state = filepath.join({config_dir, "state.json"})
	state.paths.library = filepath.join({data_dir, "library.sqlite"})

	library_init(&state.library, state.paths.playlists_folder) or_return
	state.stream = sys.audio_create_stream(_audio_stream_callback, _audio_event_callback, state) or_return
	set_paused(state, true)
	
	library_load_from_file(&state.library, state.paths.library)
	library_scan_playlists(&state.library)

	load_state(state)
	
	for &b in state.output_copy.buffers {
		util.rb_init(&b)
	}

	ok = true
	return
}

clean_up :: proc(state: ^Server) {
	save_state(state)
	library_save_to_file(state.library, state.paths.library)
	library_destroy(&state.library)
	sys.audio_destroy_stream(&state.stream)
}

queue_files_for_scanning :: proc(state: ^Server, files: []Path) {
	for file in files {
		append(&state.scan_queue, file)
	}
}

save_state :: proc(state: ^Server) {
	state.saved_state.enable_shuffle = state.enable_shuffle
	state.saved_state.playback_mode = state.playback_mode

	data, marshal_error := json.marshal(state.saved_state)
	if marshal_error != nil {return}
	defer delete(data)

	os2.remove(state.paths.state)
	file, file_error := os2.create(state.paths.state)
	if file_error != nil {return}
	defer os2.close(file)

	os2.write(file, data)
}

load_state :: proc(state: ^Server) {
	ss: _Saved_State

	data, read_error := os2.read_entire_file_from_path(state.paths.state, context.allocator)
	if read_error != nil {return}
	if json.unmarshal(data, &ss) != nil {return}

	set_shuffle_enabled(state, ss.enable_shuffle)
	set_playback_mode(state, ss.playback_mode)
	state.saved_state = ss
}

flush_scan_queue :: proc(state: ^Server) {
	if !_background_scan_is_running(state.background_scan) && len(state.scan_queue) > 0 {
		_begin_background_scan(&state.background_scan, state.scan_queue[:], state.wake_proc)
		delete(state.scan_queue)
		state.scan_queue = nil
	}
}

Scan_Progress :: struct {
	counting_files: bool,
	input_file_count: int,
	files_scanned: int,
}

get_background_scan_progress :: proc(state: Server) -> (progress: Scan_Progress, is_running: bool) {
	if _background_scan_is_running(state.background_scan) {
		is_running = true
		progress.counting_files = !state.background_scan.files_counted
		progress.files_scanned = len(state.background_scan.output.metadata)
		progress.input_file_count = state.background_scan.file_count
		return
	}

	return
}

play_track :: proc(state: ^Server, filename: string, track_id: Track_ID, dont_drop_buffer := false) -> bool {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	if !dont_drop_buffer {sys.audio_drop_buffer(&state.stream)}
	decoder.open(&state.decoder, filename, &state.current_track_info) or_return
	state.current_track_id = track_id
	set_paused(state, false, no_lock=true)

	send_event(state, Current_Track_Changed_Event{track_id = track_id})

	return true
}

seek_to_second :: proc(state: ^Server, second: int) {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	decoder.seek(&state.decoder, second)
	sys.audio_drop_buffer(&state.stream)
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
		if paused {
			sys.audio_pause(&state.stream)
			state.paused = paused
			send_event(state, State_Changed_Event{paused = state.paused})
		}
		else if decoder.is_open(state.decoder) {
			sys.audio_resume(&state.stream)
			state.paused = paused
			send_event(state, State_Changed_Event{paused = state.paused})
		}
	}
}

is_paused :: proc(state: Server) -> bool {return state.paused}
is_stopped :: proc(state: Server) -> bool {return !decoder.is_open(state.decoder)}

set_shuffle_enabled :: proc(state: ^Server, value: bool) {
	if value && !state.queue_is_shuffled {
		rand.shuffle(state.queue[:])
		state.queue_is_shuffled = true
		state.queue_serial += 1
	}

	state.enable_shuffle = value
}

set_playback_mode :: proc(state: ^Server, mode: Playback_Mode) {
	state.playback_mode = mode
}

set_volume :: proc(state: ^Server, volume: f32) {
	sys.audio_set_volume(&state.stream, volume)
}

get_volume :: proc(state: ^Server) -> f32 {
	return sys.audio_get_volume(&state.stream)
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
	state.queue_serial += 1
}

append_to_queue :: proc(sv: ^Server, tracks: []Track_ID, from_playlist: Playlist_ID) {
	if from_playlist != sv.current_playlist_id {
		sv.current_playlist_id = {}
	}

	shuffle_range_start := len(sv.queue)
	shuffle_range_end := shuffle_range_start
	sv.queue_serial += 1

	for track in tracks {
		if !slice.contains(sv.queue[:], track) {
			append(&sv.queue, track)
			shuffle_range_end += 1
		}
	}

	assert(shuffle_range_end <= len(sv.queue))
	
	if sv.enable_shuffle {
		if shuffle_range_end <= len(sv.queue) {
			rand.shuffle(sv.queue[shuffle_range_start:shuffle_range_end])
		}
	}
}

remove_tracks_from_queue :: proc(state: ^Server, tracks: []Track_ID) {
	removed: bool
	for track in tracks {
		index := slice.linear_search(state.queue[:], track) or_continue
		removed = true
		ordered_remove(&state.queue, index)
	}
	if removed {state.queue_serial += 1}
}
 
sort_queue :: proc(state: ^Server, spec: Track_Sort_Spec) {
	library_sort_tracks(state.library, state.queue[:], spec)
	state.queue_serial += 1
}

play_prev_track :: proc(state: ^Server, dont_drop_buffer := false) {
	set_queue_position(state, state.queue_pos-1, dont_drop_buffer)
}

play_next_track :: proc(state: ^Server, dont_drop_buffer := false) {
	if state.playback_mode == .Playlist && state.queue_pos == len(state.queue)-1 {
		stop_playback(state)
		return
	}

	set_queue_position(state, state.queue_pos+1, dont_drop_buffer)
}

stop_playback :: proc(state: ^Server) {
	log.info("Stopping playback...")
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)
	state.current_track_id = 0
	state.current_playlist_id = {}
	decoder.close(&state.decoder)
	clear(&state.queue)
	state.queue_serial += 1
	set_paused(state, true, true)
}

set_queue_position :: proc(state: ^Server, pos: int, dont_drop_buffer := false) -> bool {
	if len(state.queue) == 0 {return false}
	state.queue_pos = pos

	if state.queue_pos >= len(state.queue) || state.queue_pos < 0 {
		state.queue_pos = 0
	}

	path_buf: [512]u8
	try_pos := state.queue_pos

	for _ in 0..=(len(state.queue)-1) {
		defer try_pos += 1
		if try_pos >= len(state.queue) {try_pos = 0}
		track_id := state.queue[try_pos]
		path := library_get_track_path(state.library, path_buf[:], track_id) or_continue
		if play_track(state, path, track_id, dont_drop_buffer) {
			state.queue_pos = try_pos
			return true
		}
	}	

	stop_playback(state)
	return false
}

set_queue_track :: proc(state: ^Server, track_id: Track_ID) -> bool {
	index := slice.linear_search(state.queue[:], track_id) or_return
	return set_queue_position(state, index)
}

audio_time_frame_from_playback :: proc(
	state: ^Server, output: [][$WINDOW_SIZE]f32,
	from_timestamp: time.Tick, delta: f32,
) -> (samplerate, channels: int, ok: bool) {
	sync.lock(&state.playback_lock)
	defer sync.unlock(&state.playback_lock)

	cpy := &state.output_copy
	frame_delta := int(math.ceil(f32(cpy.samplerate) * delta))

	for ch in 0..<cpy.channels {
		util.rb_consume(&cpy.buffers[ch], output[ch][:], frame_delta)
	}

	return cpy.samplerate, cpy.channels, true
}

// This is being called on the audio thread!
@(private="file")
_update_output_copy_buffers :: proc(state: ^Server, input: []f32, channels, samplerate: int) {
	cpy := &state.output_copy

	if cpy.channels != channels || cpy.samplerate != samplerate {
		_clear_output_copy_buffer(state)
	}

	cpy.channels = channels
	cpy.samplerate = samplerate

	for ch in 0..<channels {
		util.rb_produce(&cpy.buffers[ch], input[:], channels, ch)
	}
}

@(private="file")
_clear_output_copy_buffer :: proc(state: ^Server) {
	for &b in state.output_copy.buffers {
		util.rb_reset(&b)
	}
}

@(private="file")
_audio_stream_callback :: proc(data: rawptr, buffer: []f32, channels, samplerate: i32) -> sys.Audio_Callback_Status {
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
_audio_event_callback :: proc(data: rawptr, event: sys.Audio_Event) {
	state := cast(^Server)data

	#partial switch event {
		case .DropBuffer: {
			sync.lock(&state.playback_lock)
			defer sync.unlock(&state.playback_lock)
			_clear_output_copy_buffer(state)
		}

		case .Finish: {
			if state.playback_mode == .RepeatSingle {
				set_queue_position(state, state.queue_pos, true)
			}
			else {
				play_next_track(state, true)
			}
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
