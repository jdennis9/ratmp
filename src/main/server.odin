package main

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
	RequestPlay,
	RequestPlayPlaylist,
}

Server_Event :: struct {
	type: Server_Event_Type,
	track: Track_ID,
	tracks: []Track_ID,
	initial_track: Maybe(Track_ID),
	playlist_uid: UID,
}

Server :: struct {
	track_arena: mem.Dynamic_Arena,
	track_allocator: mem.Allocator,
	playback_thread: Playback_Thread,
	tracks: hm.Dynamic_Handle_Map(Track, Track_ID),
	tracks_serial: uint,
	event_signal: sync.Auto_Reset_Event,
	event_queue: [dynamic]Server_Event,
	event_queue_lock: sync.Mutex,
	playback: Playback_Queue,
	queue_uid: UID,
	track_info: Audio_File_Info,
	current_track_id: Track_ID,
	playlists: hm.Static_Handle_Map(256, Playlist, Playlist_Handle),
	playlists_serial: uint,
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

	when ODIN_OS == .Windows {
		files, error := os.read_all_directory_by_path("D:\\Media\\Music\\Good", context.allocator)
	}
	else {
		files, error := os.read_all_directory_by_path("/mnt/storage/Media/Music/Good", context.allocator)
	}

	if error != nil {
		log.error(error)
	}
	else {
		for file in files {
			playback_queue_add(&sv.playback, {
				server_add_track_from_file(sv, file.fullpath) or_else {}
			}, 0)
		}
		os.file_info_slice_delete(files, context.allocator)
	}

	return true
}

server_shutdown :: proc(sv: ^Server) {
	playback_thread_destroy(&sv.playback_thread)
	hm.dynamic_destroy(&sv.tracks)
	delete(sv.event_queue)
	sv.event_queue = nil
}

server_add_track :: proc(sv: ^Server, track: Track) -> (Track_ID, bool) {
	handle, error := hm.add(&sv.tracks, track)
	if error != nil {
		log.error(error)
		return {}, false
	}
	sv.tracks_serial += 1
	return handle, true
}

read_audio_file_metadata :: proc(path: string, allocator: mem.Allocator) -> (track: Track, found: bool) {
	file: taglib.File

	when ODIN_OS == .Windows {
		path_utf16: [512]u16
		utf16.encode_string(path_utf16[:511], path)

		file = taglib.file_new_wchar(cstring16(&path_utf16[0]))
	}
	else {
		path_cstring := strings.clone_to_cstring(path, context.allocator)
		defer delete(path_cstring)

		file = taglib.file_new(path_cstring)
	}
	
	if file == nil do return
	defer taglib.file_free(file)
	
	track.url = strings.clone(path, allocator)
	
	tag := taglib.file_tag(file)
	if tag != nil {
		found = true
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

	audio_props := taglib.file_audioproperties(file)
	if audio_props != nil {
		found = true
		track.bitrate_kbps = auto_cast taglib.audioproperties_bitrate(audio_props)
		track.duration_seconds = auto_cast taglib.audioproperties_length(audio_props)
		track.samplerate = auto_cast taglib.audioproperties_samplerate(audio_props)
		track.channels = auto_cast taglib.audioproperties_channels(audio_props)
	}

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

	return true
}

server_handle_events :: proc(sv: ^Server) {
	sync.lock(&sv.event_queue_lock)
	defer sync.unlock(&sv.event_queue_lock)
	defer clear(&sv.event_queue)

	for ev in sv.event_queue {
		defer delete(ev.tracks)

		switch ev.type {

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

		case .RequestPlay:
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

server_get_queue :: proc(sv: ^Server) -> []Track_ID {
	return sv.playback.tracks[:]
}

server_move_queue_to_track :: proc(sv: ^Server, track: Track_ID) {
	playback_queue_set_track(&sv.playback, track)
	server_send_event(sv, Server_Event{type = .RequestPlay, track = track})
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
