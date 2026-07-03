package library

import "core:strings"
import "core:sort"

Sort_Order :: enum u8 {
	None,
	Ascending,
	Descending,
}

Track_Sort_Metric :: enum u8 {
	Artist,
	Album,
	Genre,
	Title,
	Duration,
	FileSize,
	FileDate,
}

Track_Sort_Spec :: struct {
	metric: Track_Sort_Metric,
	order:  Sort_Order,
}

Track_Metric_Compare_Proc :: #type proc(a, b: Track) -> bool

TRACK_METRIC_COMPARE_PROCS := [Track_Sort_Metric]Track_Metric_Compare_Proc {
	.Artist = proc(a, b: Track) -> bool {
		if len(a.artists) == 0 do return true
		if len(b.artists) == 0 do return false
		return strings.compare(get_shared_string(.Artist, a.artists[0]), get_shared_string(.Artist, b.artists[0])) < 0
	},
	.Album = proc(a, b: Track) -> bool {
		return strings.compare(get_shared_string(.Album, a.album), get_shared_string(.Album, b.album)) < 0
	},
	.Genre = proc(a, b: Track) -> bool {
		if len(a.genres) == 0 do return true
		if len(b.genres) == 0 do return false
		return strings.compare(get_shared_string(.Genre, a.genres[0]), get_shared_string(.Genre, b.genres[0])) < 0
	},
	.Title    = proc(a, b: Track) -> bool {return strings.compare(a.title, b.title) < 0},
	.Duration = proc(a, b: Track) -> bool {return a.duration < b.duration},
	.FileSize = proc(a, b: Track) -> bool {return a.file_size < b.file_size},
	.FileDate = proc(a, b: Track) -> bool {return a.file_date < b.file_date},
}

sort_tracks :: proc(tracks: []Track, spec: Track_Sort_Spec) {
	_Ctx :: struct {
		tracks: []Track,
		metric: Track_Sort_Metric,
	}

	ctx: _Ctx
	iface: sort.Interface

	ctx.tracks = tracks
	ctx.metric = spec.metric

	iface.collection = &ctx

	iface.len = proc(iface: sort.Interface) -> int {
		col := cast(^_Ctx) iface.collection
		return len(col.tracks)
	}

	iface.swap = proc(iface: sort.Interface, a, b: int) {
		col := cast(^_Ctx) iface.collection
		col.tracks[a], col.tracks[b] = col.tracks[b], col.tracks[a]
	}

	iface.less = proc(iface: sort.Interface, a, b: int) -> bool {
		col := cast(^_Ctx) iface.collection
		A, B := col.tracks[a], col.tracks[b]
		return TRACK_METRIC_COMPARE_PROCS[col.metric](A, B)
	}
}

sort_track_ids :: proc(ids: []Track_ID, spec: Track_Sort_Spec) {
	tracks := get_tracks(ids, context.allocator)
	defer delete(tracks)

	sort_tracks(tracks, spec)

	for t, i in tracks do ids[i] = t.handle
}

Playlist_Sort_Metric :: enum {
	Title,
	Duration,
	Length,
	FileSize,
}

Playlist_Sort_Spec :: struct {
	metric: Playlist_Sort_Metric,
	order:  Sort_Order,
}
