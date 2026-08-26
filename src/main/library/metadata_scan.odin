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

import "core:sync"
import "core:path/filepath"
import "src:main/shared"
import "core:os"
import "core:strings"
import "core:thread"
import "core:mem"

Metadata_Scan :: struct {
	tracks_scanned:    int,
	cover_art_scanned: int,
	dirs_scanned:      int,
	dirs_found:        int,
	is_running:        bool,
	is_done:           bool,
}

@(private="file")
_Scan_Ctx :: struct {
	input:     []string,
	arena:     mem.Dynamic_Arena,
	overwrite: bool,
	progress:  ^Metadata_Scan,
}

@(private="file")
_scan_thread_proc :: proc() {
	ctx := cast(^_Scan_Ctx) context.user_ptr
	defer mem.dynamic_arena_destroy(&ctx.arena)
	defer free(ctx)

	defer sync.atomic_store(&ctx.progress.is_running, false)
	defer sync.atomic_store(&ctx.progress.is_done, true)

	_Output_Track :: struct {
		tags: Track_Tags,
		url:  string,
	}

	_Output_Art :: struct {
		folder: string,
		art:    string,
	}

	_Output_Item :: union {
		_Output_Track,
		_Output_Art,
	}

	_Output :: struct {
		tracks:    [dynamic]Track_Add_Info,
		cover_art: [dynamic]Cover_Art_Add_Info,
		progress: ^Metadata_Scan,
	}

	allocator := mem.dynamic_arena_allocator(&ctx.arena)

	output: _Output
	output.tracks = make_dynamic_array_len_cap([dynamic]Track_Add_Info, 0, 4096, allocator)
	output.cover_art = make_dynamic_array_len_cap([dynamic]Cover_Art_Add_Info, 0, 512, allocator)
	output.progress = ctx.progress

	scan_item :: proc(path: string, allocator: mem.Allocator, output: ^_Output) -> shared.Error {
		if !os.exists(path) do return nil

		if os.is_dir(path) {
			f := os.open(path) or_return
			iter := os.read_directory_iterator_create(f)
			defer os.read_directory_iterator_destroy(&iter)

			sync.atomic_add(&output.progress.dirs_scanned, 1)

			for item in os.read_directory_iterator(&iter) {
				scan_item(item.fullpath, allocator, output)
			}
		}
		else {
			ext := filepath.ext(path)
			audio_format, is_audio := audio_file_format_from_extension(filepath.ext(path))

			if is_audio {
				tags := read_tags(path, allocator) or_return
				append(&output.tracks, Track_Add_Info {
					tags = tags,
					url  = strings.join({"file://", path}, "", allocator)
				})
				sync.atomic_add(&output.progress.tracks_scanned, 1)
			}
			else {
				switch ext {
				case ".jpg", ".jpeg", ".png", ".webm", ".bmp", ".tga":
					append(&output.cover_art, Cover_Art_Add_Info {
						folder   = filepath.dir(path),
						img_path = strings.clone(path, allocator),
					})
				}
				sync.atomic_add(&output.progress.cover_art_scanned, 1)
			}
		}

		return nil
	}

	for item in ctx.input {
		scan_item(item, allocator, &output)
	}

	send_event(Add_Tracks_Event {output.tracks[:]})
	send_event(Add_Cover_Art_Event {output.cover_art[:]})
}

// Clones the input and spawns a background thread for scanning metadata.
start_background_metadata_scan :: proc(
	input: []string, progress: ^Metadata_Scan
) {
	sync.atomic_store(&progress.is_running, true)
	sc := new(_Scan_Ctx)
	
	// Set up allocator
	mem.dynamic_arena_init(&sc.arena)
	input_allocator := mem.dynamic_arena_allocator(&sc.arena)

	// Clone input
	sc.progress = progress
	sc.input = make([]string, len(input), input_allocator)
	for s, i in input {
		sc.input[i] = strings.clone(s, input_allocator)
	}

	ctx := context
	ctx.user_ptr = sc

	thread.run(_scan_thread_proc, ctx, .Low)
}
