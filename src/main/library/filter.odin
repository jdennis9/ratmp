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
package library

import "core:testing"
import "core:mem"
import "core:strings"

Track_Filter_Metric :: enum u8 {URL, Album, Artist, Genre, Title}
Track_Filter_Metrics :: bit_set[Track_Filter_Metric]

Track_Filter_Spec :: struct {
	text:    string,
	metrics: Track_Filter_Metrics,
}

// Filters the tracks in-place and returns the newly sized slice of tracks
// WARNING: This breaks sort order, use it before sorting!!
@require_results
filter_tracks :: proc(input: []Track_ID, spec: Track_Filter_Spec) -> []Track_ID {
	text_buf:       mem.Scratch
	text_allocator: mem.Allocator
	count := 0
	input := input

	if len(input) == 0 do return input

	filter_lower := strings.to_lower(spec.text)
	defer delete(filter_lower)

	mem.scratch_init(&text_buf, 4096)
	defer mem.scratch_destroy(&text_buf)

	text_allocator = mem.scratch_allocator(&text_buf)

	for track_index := 0; track_index < len(input); track_index += 1 {
		track := get_track(input[track_index]) or_continue
		mem.scratch_free_all(&text_buf)
		pass := false

		if .URL in spec.metrics {
			url := strings.to_lower(track.url, text_allocator)
			pass |= strings.contains(url, filter_lower)
		}

		if !pass && .Album in spec.metrics && track.album != nil {
			album_name := get_shared_string_lower(.Album, track.album.?)
			pass |= strings.contains(album_name, filter_lower)
		}

		if !pass && .Artist in spec.metrics {
			for i in track.artists {
				s := get_shared_string_lower(.Artist, i)
				pass |= strings.contains(s, filter_lower)
			}
		}

		if !pass && .Genre in spec.metrics {
			for i in track.genres {
				s := get_shared_string_lower(.Genre, i)
				pass |= strings.contains(s, filter_lower)
			}
		}

		if !pass && .Title in spec.metrics {
			title := strings.to_lower(track.title, text_allocator)
			pass |= strings.contains(title, filter_lower)
		}

		if !pass {
			input[track_index] = input[len(input)-1]
			input = input[:len(input)-1]
			track_index -= 1
		}
	}

	return input
}

@test
test_filter_tracks :: proc(t: ^testing.T) {
	testing.expect(t, init({}) == nil)
	defer shutdown()

	{
		track := Track_Tags {
			title      = "Foo",
			artist     = "RAT",
			bitrate    = 1000,
			channels   = 2,
			samplerate = 48000,
			duration   = 360,
			track      = 1,
			year       = 2001,
			file_size  = 1000000,
		}

		add_track(track, "file://C:/Music/Computer_Music.mp3")
	}

	{
		track := Track_Tags {
			title      = "Bar",
			artist     = "RAT",
			bitrate    = 1000,
			channels   = 2,
			samplerate = 48000,
			duration   = 360,
			track      = 1,
			year       = 2001,
			file_size  = 1000000,
		}

		add_track(track, "file://C:/Music/Computer_Music.mp3")
	}

	{
		track := Track_Tags {
			title      = "FooBar",
			artist     = "RAT",
			bitrate    = 1000,
			channels   = 2,
			samplerate = 48000,
			duration   = 360,
			track      = 1,
			year       = 2001,
			file_size  = 1000000,
		}

		add_track(track, "file://C:/Music/Computer_Music.mp3")
	}

	tracks := get_all_track_ids(context.allocator)
	defer delete(tracks)

	testing.expect(t, len(tracks) == 3)

	tracks = filter_tracks(tracks, {
		metrics = ~{},
		text    = "RAT"
	})
	testing.expect(t, len(tracks) == 3)

	tracks = filter_tracks(tracks, {
		metrics = ~{},
		text    = "Foo",
	})
	testing.expect(t, len(tracks) == 2)

	tracks = filter_tracks(tracks, {
		metrics = ~{},
		text    = "asifjsdf",
	})
	testing.expect(t, len(tracks) == 0)
}
