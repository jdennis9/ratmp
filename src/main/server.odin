package main

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

Track_ID :: hm.Handle32

Playback_State :: enum {
	Stopped,
	Paused,
	Playing,
}

Track_Property_ID :: enum {
	Album,
	Artist,
	Genre,
}

Track_Property :: struct #raw_union {
	str: string,
	num: int,
}

Track_Flag :: enum {
	Missing,
}

Track :: struct {
	handle: Track_ID,
	url: string,

	artist,
	album,
	genre,
	title: string,

	duration_seconds,
	track_no,
	release_year,
	bitrate_kbps,
	channels,
	samplerate: int,

	flags: bit_set[Track_Flag],
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
	runner: ^thread.Thread,
	queue_arena: mem.Dynamic_Arena,
	queue: [dynamic]string,
	queue_lock: sync.Mutex,
	output_arena: mem.Dynamic_Arena,
	output: [dynamic]Track,
}

Server :: struct {
	track_arena: mem.Dynamic_Arena,
	track_allocator: mem.Allocator,
	playback_thread: Playback_Thread,
	playback_state: Playback_State,
	tracks: hm.Dynamic_Handle_Map(Track, Track_ID),
	tracks_serial: uint,
	// Map track url hash -> handle for keeping track of which
	// files are already in the library
	track_url_hash_map: map[u64]Track_ID,
	event_signal: sync.Auto_Reset_Event,
	event_queue: [dynamic]Server_Event,
	event_queue_lock: sync.Mutex,
	playback: Playback_Queue,
	queue_uid: UID,
	track_info: Audio_File_Info,
	current_track_id: Track_ID,
	playlists: hm.Static_Handle_Map(256, Playlist, Playlist_Handle),
	playlists_serial: uint,
	background_scan: Server_Background_Scan_State,
	need_background_scan: bool,
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
		for ch in 0..<spec.channels do output[ch] = make([]f32, frame_count)
		defer for ch in 0..<spec.channels do delete(output[ch])

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
	sv.tracks_serial = 1

	mem.dynamic_arena_init(&sv.track_arena)
	sv.track_allocator = mem.dynamic_arena_allocator(&sv.track_arena)

	playback_thread_init(&sv.playback_thread, {})

	mem.dynamic_arena_init(&sv.background_scan.output_arena)
	mem.dynamic_arena_init(&sv.background_scan.queue_arena)
	sv.background_scan.runner = thread.create(_background_scan_proc)
	sv.background_scan.runner.data = sv
	sv.background_scan.runner.init_context = context
	thread.start(sv.background_scan.runner)

	return true
}

server_shutdown :: proc(sv: ^Server) {
	playback_thread_destroy(&sv.playback_thread)
	hm.dynamic_destroy(&sv.tracks)
	delete(sv.event_queue)
	sv.event_queue = nil
}

track_clone :: proc(track: Track, allocator: mem.Allocator) -> (output: Track, error: mem.Allocator_Error) {
	if track.album != "" do output.album = strings.clone(track.album, allocator) or_return
	if track.artist != "" do output.artist = strings.clone(track.artist, allocator) or_return
	if track.genre != "" do output.genre = strings.clone(track.genre, allocator) or_return
	if track.title != "" do output.title = strings.clone(track.title, allocator) or_return
	output.url = strings.clone(track.url, allocator)
	output.bitrate_kbps = track.bitrate_kbps
	output.channels = track.channels
	output.duration_seconds = track.duration_seconds
	output.flags = track.flags
	output.release_year = track.release_year
	output.samplerate = track.samplerate
	output.track_no = track.track_no
	return output, nil
}

server_add_track :: proc(sv: ^Server, track: Track, update_existing := false) -> (Track_ID, bool) {
	hash := hash_track_url(track.url)
	if hash == 0 do return {}, false

	if existing_handle, exists := sv.track_url_hash_map[hash]; exists {
		if update_existing {
			if ptr, found := hm.get(&sv.tracks, existing_handle); found {
				ptr^ = track
				return existing_handle, true
			}
			else {
				delete_key(&sv.track_url_hash_map, hash)
			}
		}
		else if hm.is_valid(&sv.tracks, existing_handle) {
			return existing_handle, true
		}
	}

	handle, error := hm.add(&sv.tracks, track)
	if error != nil {
		log.error(error)
		return {}, false
	}
	sv.track_url_hash_map[hash] = handle
	sv.tracks_serial += 1
	return handle, true
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

read_audio_file_metadata :: proc(path: string, allocator: mem.Allocator) -> (track: Track, found: bool) {
	file := taglib_open(path)

	if file == nil {
		log.warn("Failed to open file", path)
		return
	}
	defer taglib.file_free(file)

	found = true
	track.url = strings.clone(path, allocator)
	
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

find_track_thumbnail :: proc(
	sv: ^Server, track_id: Track_ID, allocator: mem.Allocator
) -> (data: []byte, mime_type: string, found: bool) {
	track := get_track(sv, track_id) or_return
	file := taglib_open(track.url)
	if file == nil do return
	defer taglib.file_free(file)

	picture_data: taglib.Complex_Property_Picture_Data
	picture_prop := taglib.complex_property_get(file, "PICTURE")
	if picture_prop == nil do return
	taglib.picture_from_complex_property(picture_prop, &picture_data)
	defer taglib.complex_property_free(picture_prop)

	data = slice.clone(picture_data.data[:picture_data.size], allocator)
	mime_type = strings.clone(string(picture_data.mimeType), allocator)
	found = true

	return
}

server_add_track_from_file :: proc(sv: ^Server, path: string) -> (track_id: Track_ID, ok: bool) {
	track := read_audio_file_metadata(path, sv.track_allocator) or_return
	return server_add_track(sv, track)
}

get_track :: proc(sv: ^Server, handle: Track_ID) -> (track: ^Track, found: bool) {
	return hm.get(&sv.tracks, handle)
}

server_wait_events :: proc(sv: ^Server) {
	sync.auto_reset_event_wait(&sv.event_signal)
	server_handle_events(sv)
}

server_get_all_tracks :: proc(sv: ^Server, allocator: mem.Allocator) -> []Track_ID {
	out := make([]Track_ID, hm.len(sv.tracks), allocator)
	it := hm.iterator_make(&sv.tracks)
	i := 0
	for track, _ in hm.iterate(&it) {
		out[i] = track.handle
		i += 1
	}

	return out[:i]
}

@(private="file")
_play_track :: proc(sv: ^Server, track_id: Track_ID) -> bool {
	sv.current_track_id = track_id
	track := get_track(sv, track_id) or_return

	playback_thread_load_track(&sv.playback_thread, track.url, &sv.track_info)

	audio_resume()

	sv.playback_state = .Playing
	media_controls_update_track(sv, track^)
	platform_set_window_title(PROGRAM_NAME_AND_VERSION, "|", track.artist, "-", track.title)

	server_send_event(sv, {type = .UpdateState})

	return true
}

server_handle_events :: proc(sv: ^Server) {
	sync.lock(&sv.event_queue_lock)

	events := slice.clone(sv.event_queue[:])
	defer delete(events)
	clear(&sv.event_queue)

	sync.unlock(&sv.event_queue_lock)

	if sv.need_background_scan {
		sv.need_background_scan = false
		sync.auto_reset_event_signal(&sv.background_scan.start_signal)
	}

	for ev in events {
		defer delete(ev.tracks)

		switch ev.type {

		case .UpdateState:
			media_controls_update_state(Media_Controls_State {
				paused = audio_is_paused(),
				have_track = sv.current_track_id != {},
				shuffle_enabled = sv.playback.enable_shuffle,
			})

		case .BackgroundScanComplete:
			tracks := sv.background_scan.output[:]
			for track in tracks {
				cloned := track_clone(track, sv.track_allocator) or_continue
				server_add_track(sv, cloned)
			}
			clear(&sv.background_scan.output)
			mem.dynamic_arena_free_all(&sv.background_scan.output_arena)
			sync.auto_reset_event_signal(&sv.background_scan.output_used_signal)
		
		case .RequestSeek:
			audio_drop_buffer()
			playback_thread_seek(&sv.playback_thread, ev.seek_target)

		case .RequestPlay:
			if audio_resume() {
				sv.playback_state = .Playing
				server_send_event(sv, {type = .UpdateState})
			}
		case .RequestPause:
			if audio_pause() {
				sv.playback_state = .Paused
				server_send_event(sv, {type = .UpdateState})
			}

		case .RequestPlayPlaylist:
			playback_thread_close_track(&sv.playback_thread)
			audio_drop_buffer()
			playback_queue_clear(&sv.playback)
			playback_queue_add(&sv.playback, ev.tracks, ev.playlist_uid)

			if ev.initial_track != nil {
				playback_queue_set_track(&sv.playback, ev.initial_track.?)
				_play_track(sv, ev.initial_track.?)
			}
			else {
				track := playback_queue_set_pos(&sv.playback, 0) or_break
				_play_track(sv, track)
			}

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

server_add_playlist :: proc(sv: ^Server, name: string) -> (handle: Playlist_Handle, ok: bool) {
	pl := Playlist {
		uid = generate_uid(),
		name_cstring = strings.clone_to_cstring(name),
		serial = 1,
	}
	pl.name = string(pl.name_cstring)

	handle = hm.add(&sv.playlists, pl) or_return
	sv.playlists_serial += 1
	
	ok = true
	return
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
	allocator := mem.dynamic_arena_allocator(&sv.background_scan.queue_arena)
	sync.lock(&sv.background_scan.queue_lock)
	append(&sv.background_scan.queue, strings.clone(path, allocator))
	sync.unlock(&sv.background_scan.queue_lock)
	sv.need_background_scan = true
	server_send_empty_event(sv)
}

@(private="file")
_background_scan_proc :: proc(t: ^thread.Thread) {
	sv := cast(^Server) t.data
	state := &sv.background_scan

	input_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&input_arena)
	defer mem.dynamic_arena_destroy(&input_arena)

	allocator := mem.dynamic_arena_allocator(&input_arena)
	output_allocator := mem.dynamic_arena_allocator(&state.output_arena)

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
		mem.dynamic_arena_free_all(&state.queue_arena)
		sync.unlock(&state.queue_lock)

		// Collect files
		files: [dynamic]os.File_Info
		defer delete(files)

		add_files :: proc(dir: string, output: ^[dynamic]os.File_Info, allocator: mem.Allocator) -> os.Error {
			df := os.read_all_directory_by_path(dir, allocator) or_return
			for file in df {
				if file.type == .Regular {
					append(output, file)
				}
				else if file.type == .Directory {
					add_files(file.fullpath, output, allocator)
				}
			}
			return nil
		}

		for i in input {
			add_files(i, &files, allocator)
			state.total_file_count = len(files)
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
		state.total_file_count = 0
		state.scanned_count = 0
	}
}
