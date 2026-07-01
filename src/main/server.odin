/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
package main

import "core:math"
import "core:sort"
import "core:time"
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
import "core:reflect"
import "src:dsp"
import resampler "src:bindings/samplerate"

Playback_State :: enum {
	Stopped,
	Paused,
	Playing,
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
	RequestStop,
	BackgroundScanComplete,
	CoverArtScanComplete,
	UpdateState,
}

Server_Event :: struct {
	type:           Server_Event_Type,
	track:          Track_ID,
	tracks:         []Track_ID, // Needs to be freed after use
	initial_track:  Maybe(Track_ID),
	playlist_uid:   UID,
	seek_target:    int,
	scanned_tracks: []Track_Data,
}

Server_Cover_Art_Scan_State :: struct {
	input: map[u64]string,
	output: map[u64]string,
}

Server :: struct {				
	allocator_map: Allocator_Map,
	allocators: struct {
		scan_output:     mem.Allocator,
		scan_queue:      mem.Allocator,
		analysis:        mem.Allocator,
		playback_thread: mem.Allocator,
		temp:            mem.Allocator,
		cover_art_scan:  mem.Allocator,
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
	cover_art_scan:       Background_Task,
	cover_art_scan_state: Server_Cover_Art_Scan_State,
	need_background_scan: bool,
	saved_library_serial: uint,
	analysis:             Analysis_Buffer,

	paths: struct {
		library_database: string,
	},

	// Used by the audio callback for storing samples
	// without the need to reallocate every time the callback
	// is ran
	audio_buffer: [AUDIO_MAX_CHANNELS][dynamic]f32,
	// Tell audio callback to reset output ring buffers when streaming
	audio_buffer_was_dropped: bool,

	track_scanner:             Track_Scanner,
	track_scanner_output_used: sync.Auto_Reset_Event,
}

Server_Library_Save_Data :: struct {
	tracks: [dynamic]Track_Data,
	folder_cover_art: map[u64]string,
}

hash_track_url :: stable_hash_string_64

server_audio_callback :: proc(
	data: rawptr, event: Audio_Callback_Event, buf: []f32, spec: Audio_Spec
) -> Audio_Callback_Status {
	sv := cast(^Server) data

	if event == .Stream {
		if !playback_thread_has_track(sv.playback_thread) {
			slice.zero(buf)
			return .Continue
		}

		if sv.audio_buffer_was_dropped {
			sv.audio_buffer_was_dropped = false
			analysis_reset(&sv.analysis)
		}

		frame_count := len(buf) / spec.channels
		output: [AUDIO_MAX_CHANNELS][]f32
		for ch in 0..<spec.channels {
			resize(&sv.audio_buffer[ch], frame_count)
			output[ch] = sv.audio_buffer[ch][:]
		}

		status := playback_thread_request_frames(&sv.playback_thread, output[:spec.channels], spec.samplerate)

		analysis_feed(&sv.analysis, output[:spec.channels], spec.samplerate)

		dsp.interlace(output[:spec.channels], buf)

		if status == .Eof {
			return .Finish
		}
	}
	else if event == .TrackFinised {
		playback_thread_close_track(&sv.playback_thread)
		server_send_event(sv, {type = .TrackFinished})
	}
	else if event == .BufferDropped {
		sv.audio_buffer_was_dropped = true
	}

	return .Continue
}

server_init :: proc(sv: ^Server) -> bool {
	sv.queue_uid = generate_uid()

	sv.allocators.scan_output = allocator_map_add_dynamic_arena(&sv.allocator_map, "scan_output")
	sv.allocators.scan_queue = allocator_map_add_dynamic_arena(&sv.allocator_map, "scan_queue")
	sv.allocators.analysis = allocator_map_add_heap(&sv.allocator_map, "analysis")
	sv.allocators.playback_thread = allocator_map_add_heap(&sv.allocator_map, "playback_thread")
	sv.allocators.temp = allocator_map_add_scratch(&sv.allocator_map, "temp", 256<<10, context.allocator, flags={.IsTemp})
	sv.allocators.cover_art_scan = allocator_map_add_scratch(&sv.allocator_map, "cover_art_scan", 64<<10, context.allocator)

	library_init(&sv.library)
	playback_thread_init(&sv.playback_thread, {}, sv.allocators.playback_thread)

	track_scanner_init(&sv.track_scanner,
		_server_consume_scan_output_proc,
		sv,
	)

	sv.paths.library_database, _ = filepath.join({global_paths.data_dir, "library.sqlite"}, context.allocator)

	analysis_init(&sv.analysis, sv.allocators.analysis)

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

	artists := library_join_track_group_names_to_allocator(sv.library, track.artists, .Artist, sv.allocators.temp)

	sv.playback_state = .Playing
	media_controls_update_track(sv, track)
	platform_set_window_title(
		PROGRAM_NAME_AND_VERSION, "|", artists, "-", track.title
	)

	if global_config.server.notify_new_track {
		notify_send("Now playing:", artists, "-", get_album_name(sv^, track.album))
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
			paused          = sv.playback_state == .Paused,
			have_track      = sv.current_track_id != 0,
			shuffle_enabled = sv.playback.enable_shuffle,
		})

	}

	library_update(&sv.library)

	if sv.library.serial != sv.saved_library_serial {
		// @TODO: Do this asynchronously somehow
		error := library_save(sv.library, sv.paths.library_database)
		sv.saved_library_serial = sv.library.serial
		if error != nil {
			log.error("Error saving library:", error)
		}
	}


	for ev in events {
		defer delete(ev.tracks)

		switch ev.type {

		case .UpdateState:
			_update_media_controls_state(sv)

		case .BackgroundScanComplete:
			for track in ev.scanned_tracks {
				library_add_track(&sv.library, track)
			}
			sync.auto_reset_event_signal(&sv.track_scanner_output_used)

		case .CoverArtScanComplete:
			output := sv.cover_art_scan_state.output
			for k, v in output {
				sv.library.folder_cover_art[k] = strings.clone(
					v, sv.library.allocators.track_data
				)
			}
			sv.library.serial += 1
			free_all(sv.allocators.cover_art_scan)
			bgtask_cancel(&sv.cover_art_scan)

		case .RequestStop:
			playback_thread_close_track(&sv.playback_thread)
			sv.current_track_id = 0
			sv.track_info = {}
			sv.playback_state = .Stopped
			platform_set_window_title(PROGRAM_NAME_AND_VERSION)
			audio_drop_buffer()

		case .RequestSeek:
			playback_thread_seek(&sv.playback_thread, ev.seek_target)
			audio_drop_buffer()

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
			
			audio_drop_buffer()
			_update_media_controls_state(sv)

		case .RequestPlayTrack:
			playback_thread_close_track(&sv.playback_thread)
			_play_track(sv, ev.track)
			audio_drop_buffer()
			
		case .PrevTrackRequested:
			playback_thread_close_track(&sv.playback_thread)
			track_id := playback_queue_prev(&sv.playback) or_break
			_play_track(sv, track_id)
			audio_drop_buffer()

		case .NextTrackRequested:
			playback_thread_close_track(&sv.playback_thread)
			track_id := playback_queue_next(&sv.playback) or_break
			_play_track(sv, track_id)
			audio_drop_buffer()
		case .TrackFinished:
			track_id := playback_queue_next(&sv.playback) or_break
			_play_track(sv, track_id)
			analysis_reset(&sv.analysis)
		}
	}
}

server_send_event :: proc(sv: ^Server, ev: Server_Event) {
	sync.lock(&sv.event_queue_lock)
	append(&sv.event_queue, ev)
	sync.unlock(&sv.event_queue_lock)

	log.debug("Server event:", ev.type)

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

server_is_paused :: proc(sv: ^Server) -> bool {
	return !playback_thread_has_track(sv.playback_thread) || audio_is_paused()
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

server_request_radio :: proc(sv: ^Server, main_track: Track_ID) {
	tracks := library_build_radio(sv.library, main_track, sv.allocators.temp)
	server_request_play_playlist(sv, tracks, generate_uid(), main_track)
}

server_request_pause :: proc(sv: ^Server) {server_send_event(sv, {type = .RequestPause})}
server_request_resume :: proc(sv: ^Server) {server_send_event(sv, {type = .RequestPlay})}
server_request_stop :: proc(sv: ^Server) {server_send_event(sv, {type = .RequestStop})}

server_send_empty_event :: proc(sv: ^Server) {
	sync.auto_reset_event_signal(&sv.event_signal)
}

server_seek :: proc(sv: ^Server, second: int) {
	server_send_event(sv, {type = .RequestSeek, seek_target = second})
}

server_get_track_position_seconds :: proc(sv: ^Server) -> int {
	return playback_thread_get_track_position(&sv.playback_thread)
}

/*server_queue_for_background_scan :: proc(sv: ^Server, path: string) {
	/*allocator := sv.allocators.scan_queue
	append(&sv.track_scan_state.inpput, strings.clone(path, allocator))
	sv.need_background_scan = true
	server_send_empty_event(sv)*/

	track_scanner_queue(&sv.track_scanner, {path})
}*/

server_start_cover_art_scan :: proc(sv: ^Server) {
	bgtask_cancel(&sv.cover_art_scan)
	free_all(sv.allocators.cover_art_scan)

	state := &sv.cover_art_scan_state
	free_all(sv.allocators.cover_art_scan)
	state.input = make(map[u64]string, sv.allocators.cover_art_scan)
	state.output = make(map[u64]string, sv.allocators.cover_art_scan)

	clear(&sv.library.folder_cover_art)

	for _, track in sv.library.tracks {
		if track.protocol != .File do continue
		dir := filepath.clean(filepath.dir(track.url), sv.allocators.temp) or_continue
		hash := stable_hash_string_64(dir)

		if hash not_in state.input {
			state.input[hash] = strings.clone(dir, sv.allocators.cover_art_scan)
		}
	}

	bgtask_run(
		&sv.cover_art_scan, _cover_art_scan_proc,
		context.allocator, sv
	)
}

server_start_metadata_refresh :: proc(sv: ^Server) {
	input := make([]Track_Scanner_Input, len(sv.library.tracks))
	defer delete(input)

	i := 0
	for _, v in sv.library.tracks {
		input[i].path = v.url
		input[i].overwrite = true
		i += 1
	}

	track_scanner_queue(&sv.track_scanner, input)
}

server_consume_audio_output :: proc(sv: ^Server, buf: [][]f32, timespan: f32) -> Audio_Spec {
	return analysis_consume(&sv.analysis, timespan, buf)
}

_cover_art_scan_proc :: proc(
	task: ^Background_Task
) -> (error: Error) {
	defer if error != nil do bgtask_consume_input(task)

	sv := cast(^Server) task.data
	state := &sv.cover_art_scan_state
	input := slice.map_values(state.input, task.allocator) or_return
	bgtask_consume_input(task)

	sync.atomic_store(&task.progress.total_items, len(state.input))

	for dir in input {
		if task.want_cancel do break
		hash := stable_hash_string_64(dir)

		state.output[hash] = scan_directory_for_cover_art(
			dir, sv.allocators.cover_art_scan, task.allocator
		) or_else ""

		log.debug(dir, state.output[hash])

		sync.atomic_add(&task.progress.items_processed, 1)
	}

	server_send_event(sv, Server_Event{type = .CoverArtScanComplete})
	return nil
}

_server_consume_scan_output_proc :: proc(data: rawptr, tracks: []Track_Data) -> Error {
	sv := cast(^Server) data

	server_send_event(sv, Server_Event {
		type = .BackgroundScanComplete,
		scanned_tracks = tracks,
	})

	sync.auto_reset_event_wait(&sv.track_scanner_output_used)
	return nil
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
		return strings.compare(library_get_artist_name(l, a.artists[0]), library_get_artist_name(l, b.artists[0]))
	},
	.Album =      proc(l: Library, a, b: Track) -> int {
		return strings.compare(library_get_album_name(l, a.album), library_get_album_name(l, b.album))
	},
	.Genre =      proc(l: Library, a, b: Track) -> int {
		return strings.compare(library_get_genre_name(l, a.genres[0]), library_get_genre_name(l, b.genres[0]))
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
