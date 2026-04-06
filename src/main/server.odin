package main

import "core:fmt"
import "src:bindings/ffmpeg"
import "core:sort"
import "core:encoding/cbor"
import "core:time"
import "core:path/slashpath"
import "core:hash/xxhash"
import "core:path/filepath"
import "core:thread"
import "core:slice"
import "core:sync"
import "core:os"
import "core:unicode/utf16"
import "core:strings"
import "core:mem"
import "src:bindings/taglib"
import "core:log"
import "base:intrinsics"
import "core:reflect"
import hm "core:container/handle_map"
import "src:dsp"

// 0 means none
// Index into array
Artist_ID :: distinct i16
Genre_ID :: distinct i16
Album_ID :: distinct i16
Dir_ID :: distinct i16

Playback_State :: enum {
	Stopped,
	Paused,
	Playing,
}

Track_Flag :: enum {
	Missing,
}

Track_Protocol :: enum u8 {
	File,
}

Server_Event_Type :: enum {
	TrackFinished,
	NextTrackRequested,
	PrevTrackRequested,
	RequestPlayTrack,
	RequestPlayPlaylist,
	RequestPlay,
	RequestPause,
	RequestSeek,
	BackgroundScanComplete,
	UpdateState,
}

Server_Event :: struct {
	type: Server_Event_Type,
	track: Track_ID,
	tracks: []Track_ID, // Needs to be freed after use
	initial_track: Maybe(Track_ID),
	playlist_uid: UID,
	seek_target: int,
}

Server_Background_Scan_State :: struct {
	// Main thread signals this to start the scan
	start_signal: sync.Auto_Reset_Event,
	// Main thread signals this to say the scan output has
	// been added to the library
	output_used_signal: sync.Auto_Reset_Event,
	total_file_count: int,
	scanned_count: int,
	scanning: bool,
	runner: ^thread.Thread,
	queue: [dynamic]string,
	queue_lock: sync.Mutex,
	output: [dynamic]Track_Data,
}

Server :: struct {				
	allocator_map: Allocator_Map,
	allocators: struct {
		scan_output: mem.Allocator,
		scan_queue: mem.Allocator,
	},

	library: Library,

	playback_thread:      Playback_Thread,
	playback_state:       Playback_State,
	event_signal:         sync.Auto_Reset_Event,
	event_queue:          [dynamic]Server_Event,
	event_queue_lock:     sync.Mutex,
	playback:             Playback_Queue,
	queue_uid:            UID,
	track_info:           Audio_File_Info,
	current_track_id:     Track_ID,
	background_scan:      Server_Background_Scan_State,
	need_background_scan: bool,
	library_path:         string,
	saved_library_serial: uint,

	// Used by the audio callback for storing samples
	// without the need to reallocate every frame
	audio_buffer: [AUDIO_MAX_CHANNELS][dynamic]f32,
}

Server_Library_Save_Data :: struct {
	tracks: [dynamic]Track_Data,
	folder_cover_art: map[u64]string,
}

hash_track_url :: proc(str: string) -> u64 {
	return xxhash.XXH3_64_default(transmute([]u8) str)
}

server_audio_callback :: proc(
	data: rawptr, event: Audio_Callback_Event, buf: []f32, spec: Audio_Spec
) -> Audio_Callback_Status {
	sv := cast(^Server) data

	if event == .Stream {
		frame_count := len(buf) / spec.channels
		output: [AUDIO_MAX_CHANNELS][]f32
		for ch in 0..<spec.channels {
			resize(&sv.audio_buffer[ch], frame_count)
			output[ch] = sv.audio_buffer[ch][:]
		}

		status := playback_thread_request_frames(&sv.playback_thread, output[:spec.channels], spec.samplerate)
		dsp.interlace(output[:spec.channels], buf)

		if status == .Eof {
			return .Finish
		}
	}
	else if event == .TrackFinised {
		server_send_event(sv, {type = .TrackFinished})
	}

	return .Continue
}

server_init :: proc(sv: ^Server) -> bool {
	sv.queue_uid = generate_uid()

	//mem.dynamic_arena_init(&sv.track_arena)
	//sv.track_allocator = mem.dynamic_arena_allocator(&sv.track_arena)
	sv.allocators.scan_output = allocator_map_add_dynamic_arena(&sv.allocator_map, "scan_output")
	sv.allocators.scan_queue = allocator_map_add_dynamic_arena(&sv.allocator_map, "scan_queue")

	library_init(&sv.library)
	playback_thread_init(&sv.playback_thread, {})

	sv.background_scan.runner = thread.create(_background_scan_proc)
	sv.background_scan.runner.data = sv
	sv.background_scan.runner.init_context = context
	thread.start(sv.background_scan.runner)

	sv.library_path, _ = filepath.join({global_paths.data_dir, "library.sqlite"}, context.allocator)


	return true
}

server_shutdown :: proc(sv: ^Server) {
	playback_thread_destroy(&sv.playback_thread)
	library_destroy(&sv.library)
	delete(sv.event_queue)
	sv.event_queue = nil
}

taglib_open :: proc(path: string) -> taglib.File {
	when ODIN_OS == .Windows {
		path_utf16: [512]u16
		utf16.encode_string(path_utf16[:511], path)

		return taglib.file_new_wchar(cstring16(&path_utf16[0]))
	}
	else {
		path_cstring := strings.clone_to_cstring(path, context.allocator)
		defer delete(path_cstring)

		return taglib.file_new(path_cstring)
	}
}

read_audio_file_metadata :: proc(path: string, allocator: mem.Allocator) -> (track: Track_Data, found: bool) {
	track.format = audio_file_format_from_extension(filepath.ext(path)) or_return

	TIME_SCOPE("TagLib probe")

	file := taglib_open(path)
	
	if file == nil {
		log.warn("Failed to open file", path)
		return
	}
	defer taglib.file_free(file)

	found = true
	track.url = strings.clone(path, allocator)
	track.protocol = .File

	if file_info, error := os.stat(path, context.allocator); error == nil {
		track.file_date = file_info.creation_time
		track.file_size = auto_cast file_info.size
		os.file_info_delete(file_info, context.allocator)
	}
	
	tag := taglib.file_tag(file)
	if tag != nil {
		defer taglib.tag_free_strings()

		title := taglib.tag_title(tag)
		artist := taglib.tag_artist(tag)
		album := taglib.tag_album(tag)
		genre := taglib.tag_genre(tag)
		year := taglib.tag_year(tag)
		track_no := taglib.tag_track(tag)

		if title != nil do track.title = strings.clone(string(title), allocator)
		if album != nil do track.album = strings.clone(string(album), allocator)
		if genre != nil do track.genre = strings.clone(string(genre), allocator)
		if artist != nil do track.artist = strings.clone(string(artist), allocator)
		track.release_year = auto_cast year
		track.track_no = auto_cast track_no
	}

	if track.title == "" {
		track.title = strings.clone(filepath.short_stem(filepath.base(path)), allocator)
	}

	audio_props := taglib.file_audioproperties(file)
	if audio_props != nil {
		track.bitrate_kbps = auto_cast taglib.audioproperties_bitrate(audio_props)
		track.duration_seconds = auto_cast taglib.audioproperties_length(audio_props)
		track.samplerate = auto_cast taglib.audioproperties_samplerate(audio_props)
		track.channels = auto_cast taglib.audioproperties_channels(audio_props)
	}

	return
}

server_wait_events :: proc(sv: ^Server) {
	sync.auto_reset_event_wait(&sv.event_signal)
	server_handle_events(sv)
}

@(private="file")
_play_track :: proc(sv: ^Server, track_id: Track_ID) -> bool {
	sv.current_track_id = track_id
	track := library_get_track(sv.library, track_id) or_return

	playback_thread_load_track(&sv.playback_thread, track.url, &sv.track_info)

	audio_resume()

	sv.playback_state = .Playing
	media_controls_update_track(sv, track)
	platform_set_window_title(
		PROGRAM_NAME_AND_VERSION, "|", get_artist_name(sv^, track.artist), "-", track.title
	)

	if global_config.server.notify_new_track {
		notify_send("Now playing:", get_artist_name(sv^, track.artist), "-", get_album_name(sv^, track.album))
	}

	server_send_event(sv, {type = .UpdateState})

	return true
}

server_handle_events :: proc(sv: ^Server) {
	sync.lock(&sv.event_queue_lock)

	events := slice.clone(sv.event_queue[:])
	defer delete(events)
	clear(&sv.event_queue)

	sync.unlock(&sv.event_queue_lock)

	_update_media_controls_state :: proc(sv: ^Server) {
		media_controls_update_state(Media_Controls_State {
			paused = sv.playback_state == .Paused,
			have_track = sv.current_track_id != {},
			shuffle_enabled = sv.playback.enable_shuffle,
		})

	}

	if sv.need_background_scan {
		sv.need_background_scan = false
		sync.auto_reset_event_signal(&sv.background_scan.start_signal)

		if global_config.server.notify_library_scan {
			notify_send("Beginning library scan")
		}
	}

	library_update(&sv.library)

	if sv.library.serial != sv.saved_library_serial {
		// @TODO: Do this asynchronously somehow
		log.debug(sv.library.serial, sv.saved_library_serial)
		library_save(sv.library, sv.library_path)
		sv.saved_library_serial = sv.library.serial
	}


	for ev in events {
		defer delete(ev.tracks)

		switch ev.type {

		case .UpdateState:
			_update_media_controls_state(sv)

		case .BackgroundScanComplete:
			tracks := sv.background_scan.output[:]
			for track in tracks {
				path_hash := stable_hash_string_64(track.url)
				if path_hash in sv.library.url_hash_map do continue
				library_add_track(&sv.library, track)
			}
			clear(&sv.background_scan.output)
			free_all(sv.allocators.scan_output)
			sync.auto_reset_event_signal(&sv.background_scan.output_used_signal)

			if global_config.server.notify_library_scan {
				notify_send("Library scan complete")
			}
		
		case .RequestSeek:
			audio_drop_buffer()
			playback_thread_seek(&sv.playback_thread, ev.seek_target)

		case .RequestPlay:
			if audio_resume() {
				sv.playback_state = .Playing
				_update_media_controls_state(sv)

				if global_config.server.notify_background_playback_state && !platform_is_window_visible() {
					notify_send("Playback resumed")
				}
			}
		case .RequestPause:
			if audio_pause() {
				sv.playback_state = .Paused
				_update_media_controls_state(sv)

				if global_config.server.notify_background_playback_state && !platform_is_window_visible() {
					notify_send("Playback paused")
				}
			}

		case .RequestPlayPlaylist:
			playback_thread_close_track(&sv.playback_thread)
			audio_drop_buffer()
			playback_queue_clear(&sv.playback)
			playback_queue_add(&sv.playback, ev.tracks, ev.playlist_uid, assume_unique=true)

			if ev.initial_track != nil {
				playback_queue_set_track(&sv.playback, ev.initial_track.?)
				_play_track(sv, ev.initial_track.?)
			}
			else {
				track := playback_queue_set_pos(&sv.playback, 0) or_break
				_play_track(sv, track)
			}

			_update_media_controls_state(sv)

		case .RequestPlayTrack:
			playback_thread_close_track(&sv.playback_thread)
			audio_drop_buffer()
			_play_track(sv, ev.track)
			
		case .PrevTrackRequested:
			playback_thread_close_track(&sv.playback_thread)
			track_id := playback_queue_prev(&sv.playback) or_break
			_play_track(sv, track_id)

		case .NextTrackRequested:
			audio_drop_buffer()
			fallthrough
		case .TrackFinished:
			playback_thread_close_track(&sv.playback_thread)
			track_id := playback_queue_next(&sv.playback) or_break
			_play_track(sv, track_id)
		}
	}

}

server_send_event :: proc(sv: ^Server, ev: Server_Event) {
	sync.lock(&sv.event_queue_lock)
	append(&sv.event_queue, ev)
	sync.unlock(&sv.event_queue_lock)

	sync.auto_reset_event_signal(&sv.event_signal)
	platform_flush_events()
}

server_request_previous_track :: proc(sv: ^Server) {
	server_send_event(sv, {type = .PrevTrackRequested})
}

server_request_next_track :: proc(sv: ^Server) {
	server_send_event(sv, {type = .NextTrackRequested})
}

server_is_shuffle_enabled :: proc(sv: ^Server) -> bool {
	return sv.playback.enable_shuffle
}

server_set_shuffle_enabled :: proc(sv: ^Server, enabled: bool) {
	playback_queue_set_shuffle_enabled(&sv.playback, enabled)
	server_send_event(sv, {type = .UpdateState})
}

server_get_queue :: proc(sv: ^Server) -> []Track_ID {
	return sv.playback.tracks[:]
}

server_move_queue_to_track :: proc(sv: ^Server, track: Track_ID) {
	playback_queue_set_track(&sv.playback, track)
	server_send_event(sv, Server_Event{type = .RequestPlayTrack, track = track})
}

server_request_play_playlist :: proc(
	sv: ^Server, tracks: []Track_ID,
	uid: UID, initial_track: Maybe(Track_ID) = nil
) {
	event := Server_Event {
		type = .RequestPlayPlaylist,
		tracks = slice.clone(tracks),
		playlist_uid = uid,
		initial_track = initial_track,
	}

	server_send_event(sv, event)
}

server_request_pause :: proc(sv: ^Server) {server_send_event(sv, {type = .RequestPause})}
server_request_resume :: proc(sv: ^Server) {server_send_event(sv, {type = .RequestPlay})}

server_send_empty_event :: proc(sv: ^Server) {
	sync.auto_reset_event_signal(&sv.event_signal)
}

server_seek :: proc(sv: ^Server, second: int) {
	server_send_event(sv, {type = .RequestSeek, seek_target = second})
}

server_get_track_position_seconds :: proc(sv: ^Server) -> int {
	return playback_thread_get_track_position(&sv.playback_thread)
}

server_queue_for_background_scan :: proc(sv: ^Server, path: string) {
	allocator := sv.allocators.scan_queue
	sync.lock(&sv.background_scan.queue_lock)
	append(&sv.background_scan.queue, strings.clone(path, allocator))
	sync.unlock(&sv.background_scan.queue_lock)
	sv.need_background_scan = true
	server_send_empty_event(sv)
}

server_is_doing_background_scan :: proc(sv: ^Server) -> bool {
	return sv.background_scan.scanning
}

server_get_background_scan_progress :: proc(sv: ^Server) -> (total_files, files_scanned: int) {
	return sv.background_scan.total_file_count, sv.background_scan.scanned_count
}

@(private="file")
_background_scan_proc :: proc(t: ^thread.Thread) {
	sv := cast(^Server) t.data
	state := &sv.background_scan

	input_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&input_arena)
	defer mem.dynamic_arena_destroy(&input_arena)

	allocator := mem.dynamic_arena_allocator(&input_arena)
	output_allocator := sv.allocators.scan_output

	for {
		input: [dynamic]string
		defer {
			delete(input)
			mem.dynamic_arena_free_all(&input_arena)
		}

		sync.auto_reset_event_wait(&state.start_signal)

		// Copy queue to local array
		sync.lock(&state.queue_lock)
		for i in state.queue {
			append(&input, strings.clone(i, allocator))
		}
		clear(&state.queue)
		free_all(sv.allocators.scan_queue)
		sync.unlock(&state.queue_lock)

		state.scanning = true

		// Collect files
		files: [dynamic]os.File_Info
		defer delete(files)

		add_files :: proc(dir: string, output: ^[dynamic]os.File_Info, counter: ^int, allocator: mem.Allocator) -> os.Error {
			df := os.read_all_directory_by_path(dir, allocator) or_return
			for file in df {
				if file.type == .Regular {
					append(output, file)
					counter^ += 1
				}
				else if file.type == .Directory {
					add_files(file.fullpath, output, counter, allocator)
				}
			}
			return nil
		}

		for i in input {
			add_files(i, &files, &state.total_file_count, allocator)
		}
		log.debug("Scanning", state.total_file_count, "files...")

		// Get metadata
		for file in files {
			track := read_audio_file_metadata(file.fullpath, output_allocator) or_continue
			assert(track.title != "")
			append(&state.output, track)
			state.scanned_count += 1
		}

		log.debug("Scanned", state.total_file_count, "files")

		server_send_event(sv, {type = .BackgroundScanComplete})
		sync.auto_reset_event_wait(&state.output_used_signal)
		state.scanning = false
		state.total_file_count = 0
		state.scanned_count = 0
	}
}

// -----------------------------------------------------------------------------
// Track sorting
// -----------------------------------------------------------------------------

Sort_Order :: enum {
	Ascending,
	Descending,
}

Track_Sort_Metric :: enum {
	Title,
	Artist,
	Album,
	Genre,
	Duration,
	FileDate,
	DateAdded,
	Track,
	Bitrate,
	Samplerate,
	Format,
}

Track_Sort_Spec :: struct {
	order: Sort_Order,
	// Name of field to sort by
	metric: Track_Sort_Metric,
}

Track_Compare_Proc :: #type proc(l: Library, a, b: Track) -> int

TRACK_METRIC_COMPARE_PROCS := [Track_Sort_Metric]Track_Compare_Proc {
	.Title =      proc(l: Library, a, b: Track) -> int {return strings.compare(a.title, b.title)},
	.Artist =     proc(l: Library, a, b: Track) -> int {
		return strings.compare(library_get_artist_name(l, a.artist), library_get_artist_name(l, b.artist))
		//return l.artists.sorted_indices[a.artist] - l.artists.sorted_indices[b.artist]
	},
	.Album =      proc(l: Library, a, b: Track) -> int {
		return strings.compare(library_get_album_name(l, a.album), library_get_album_name(l, b.album))
	},
	.Genre =      proc(l: Library, a, b: Track) -> int {
		return strings.compare(library_get_genre_name(l, a.genre), library_get_genre_name(l, b.genre))
	},
	.Duration =   proc(l: Library, a, b: Track) -> int {return auto_cast (a.duration_seconds - b.duration_seconds)},
	.Track =      proc(l: Library, a, b: Track) -> int {return auto_cast (a.track_no - b.track_no)},
	.FileDate =   proc(l: Library, a, b: Track) -> int {return auto_cast time.diff(a.file_date, b.file_date)},
	.DateAdded =  proc(l: Library, a, b: Track) -> int {return auto_cast time.diff(a.date_added, b.date_added)},
	.Bitrate =    proc(l: Library, a, b: Track) -> int {return auto_cast (a.bitrate_kbps - b.bitrate_kbps)},
	.Samplerate = proc(l: Library, a, b: Track) -> int {return auto_cast (a.samplerate - b.samplerate)},
	.Format =     proc(l: Library, a, b: Track) -> int {
		return strings.compare(
			reflect.enum_name_from_value(a.format) or_else "",
			reflect.enum_name_from_value(b.format) or_else ""
		)
	},
}

// Metrics to fall back to when a two tracks have the same value
TRACK_METRIC_NEXT_METRIC := #partial [Track_Sort_Metric]Maybe(Track_Sort_Metric) {
	.Artist = .Album,
	.Album = .Title,
	.Genre = .Album,
	.FileDate = .Album,
	.DateAdded = .Album,
	.Track = .Album,
}

sort_tracks :: proc(sv: ^Server, tracks: []Track_ID, spec: Track_Sort_Spec) {
	Collection :: struct {
		sv: ^Server,
		tracks: []Track_ID,
		metric: Track_Sort_Metric,
	}

	col := Collection {
		sv = sv,
		tracks = tracks,
		metric = spec.metric,
	}

	iface := sort.Interface {
		collection = &col,
		len = proc(it: sort.Interface) -> int {
			col := cast(^Collection) it.collection
			return len(col.tracks)
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			col := cast(^Collection) it.collection
			cmp_proc := TRACK_METRIC_COMPARE_PROCS[col.metric]
			A := library_get_track(col.sv.library, col.tracks[a]) or_return
			B := library_get_track(col.sv.library, col.tracks[b]) or_return

			r: int

			metric := col.metric
			r = cmp_proc(col.sv.library, A, B)

			for abs(r) == 0 && TRACK_METRIC_NEXT_METRIC[metric] != nil {
				metric = TRACK_METRIC_NEXT_METRIC[metric].?
				cmp_proc = TRACK_METRIC_COMPARE_PROCS[metric]
				r = cmp_proc(col.sv.library, A, B)
			}

			return r < 0
		},
		swap = proc(it: sort.Interface, a, b: int) {
			col := cast(^Collection) it.collection
			col.tracks[a], col.tracks[b] = col.tracks[b], col.tracks[a]
		},
	}

	if spec.order == .Descending do sort.reverse_sort(iface)
	else do sort.sort(iface)
}
