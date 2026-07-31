package c_interface

import "src:main/player"
import "src:main/shared"
import "src:dsp"
import "core:path/filepath"
import "core:slice"
import "base:runtime"
import lib "src:main/library"

g_ctx: runtime.Context

g: struct {
	paths: struct {
		config: string,
		data:   string,
		cache:  string,
	},
}

_sv :: proc(s: string) -> String_View {
	return {
		data = raw_data(s),
		len  = auto_cast len(s),
	}
}

_sv_to_string :: proc(sv: String_View) -> string {
	return string(slice.from_ptr(sv.data, auto_cast sv.len))
}

_init :: proc "c" () -> shared.Error {
	g_ctx = runtime.default_context()
	context = g_ctx

	// --------------------------------------------------------------------------
	// Get paths
	// --------------------------------------------------------------------------
	when ODIN_DEBUG || ODIN_OS == .Windows {
		g.paths.config = "."
		g.paths.data   = "."
		g.paths.cache  = "." + filepath.SEPARATOR_STRING + "cache"

		shared.ensure_dir(g.paths.cache)
	}
	else {
		g.paths.config = os.user_config_dir(context.allocator) or_return
		g.paths.data   = os.user_data_dir(context.allocator) or_return
		g.paths.cache  = os.user_cache_dir(context.allocator) or_return
		g.paths.config = filepath.join({g.paths.config, "ratmp"}) or_return
		g.paths.data   = filepath.join({g.paths.data, "ratmp"}) or_return
		g.paths.cache  = filepath.join({g.paths.cache, "ratmp"}) or_return
	}

	lib.init({
		metadata_db_path = filepath.join({g.paths.config, "metadata.dat"}) or_return
	}) or_return

	player.init({
	}) or_return

	return nil
}

@(export, link_name="ratmp_init")
init :: proc "c" (argc: i32, argv: [^]cstring) -> b8 {
	err := _init()
	return err == nil
}

@(export, link_name="ratmp_shutdown")
shutdown :: proc "c" () {
	context = g_ctx
}

@(export, link_name="ratmp_free")
_free :: proc "c" (ptr: rawptr) {
	context = g_ctx
	free(ptr)
}

@(export, link_name="ratmp_play_file")
play_file :: proc "c" (path: String_View) -> b8 {
	context = g_ctx
	player.play_url(_sv_to_string(path)) or_return

	return true
}

@(export, link_name="ratmp_pause")
pause :: proc "c" () {
	context = g_ctx
	player.set_paused(true)
}

@(export, link_name="ratmp_resume")
resume :: proc "c" () {
	context = g_ctx
	player.set_paused(false)
}

@(export, link_name="ratmp_next")
next :: proc "c" () {
	context = g_ctx
	player.play_next_track()
}

@(export, link_name="ratmp_prev")
prev :: proc "c" () {
	context = g_ctx
	player.play_prev_track()
}


@(export, link_name="ratmp_get_track")
get_track :: proc "c" (id: Track_ID, out: ^Track) -> b8 {
	context = g_ctx
	track := lib.get_track(transmute(lib.Track_ID) id) or_return

	out.url          = _sv(track.url)
	out.title        = _sv(track.title)
	out.artists      = auto_cast raw_data(track.artists)
	out.artist_count = auto_cast len(track.artists)
	out.genres       = auto_cast raw_data(track.genres)
	out.genre_count  = auto_cast len(track.genres)
	out.track        = track.track
	out.bitrate      = track.bitrate
	out.channels     = track.channels
	out.samplerate   = track.samplerate
	out.duration     = track.duration
	out.year         = track.year
	out.file_date    = track.file_date
	out.file_size    = track.file_size
	out.has_album    = track.album != nil
	out.album        = auto_cast(track.album.? or_else 0)

	return true
}

@(export, link_name="ratmp_get_all_track_ids")
get_all_track_ids :: proc "c" (out: ^[^]Track_ID) -> i32 {
	context = g_ctx
	ids := lib.get_all_track_ids(context.allocator)
	out^ = auto_cast raw_data(ids)
	return auto_cast len(ids)
}

@(export, link_name="ratmp_get_shared_string")
get_shared_string :: proc "c" (type: i32, id: Shared_String_ID) -> String_View {
	context = g_ctx
	if (type < 0) || (type >= i32(max(lib.Shared_String_Type))) do return {}
	return _sv(lib.get_shared_string(auto_cast type, auto_cast id))
}

@(export, link_name="ratmp_play_playlist")
play_playlist :: proc "c" (tracks: [^]lib.Track_ID, track_count: i32, playlist_id: u64) {
	context = g_ctx
	player.play_playlist(tracks[:track_count], auto_cast playlist_id)
}

@(export, link_name="ratmp_consume_output")
consume_output :: proc "c" (buffer: [^][^]f32, buffer_channels: i32, buffer_size: i32, timespan: f32, samplerate: ^i32, channels: ^i32) {
	context = g_ctx

	b: [player.MAX_CHANNELS][]f32
	for ch in 0..<buffer_channels {
		b[ch] = buffer[ch][:buffer_size]
	}

	spec := player.consume_output(b[:buffer_channels], timespan)

	samplerate^ = auto_cast spec.samplerate
	channels^   = auto_cast spec.channels
}

@(export, link_name="ratmp_new_fft")
fft_new :: proc "c" () -> ^dsp.FFT_State {
	context = g_ctx
	return new(dsp.FFT_State)
}

@(export, link_name="ratmp_destroy_fft")
fft_destroy :: proc "c" (state: ^dsp.FFT_State) {
	context = g_ctx
	dsp.fft_destroy(state)
	free(state)
}

@(export, link_name="ratmp_fft")
fft :: proc "c" (state: ^dsp.FFT_State, input: [^]f32, input_count: i32, output: ^[^]f32, output_count: ^i32) {
	context = g_ctx
	dsp.fft_process(state, input[:input_count])
	output^ = raw_data(state.real_buffer)
	output_count^ =  auto_cast len(state.real_buffer)
}
