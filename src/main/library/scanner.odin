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

// =============================================================================
// Utility for scanning files to add to the library on a background thread
// =============================================================================

import "src:main/shared"
import "core:slice"
import "core:path/filepath"
import "core:path/slashpath"
import "core:log"
import "core:testing"
import "core:strings"
import "core:sync"
import "core:mem"
import "core:thread"
import "core:os"

FILE_SCANNER_SCRATCH_SIZE :: (32<<10)

Scanned_Track :: struct {
	tags: Track_Tags,
	url:  string,
}

Scanned_Art :: struct {
	folder: string,
	image:  string,
}

Scanned_Item :: struct {
	variant: union {
		Scanned_Track,
		Scanned_Art,
	},
	overwrite: bool,
}

Scanner_Input :: struct {
	path:      string,
	overwrite: bool,
}

Scanner_Progress :: struct {
	scanned_items, total_items, scanned_files: int,
}

Scanner :: struct {
	worker:   shared.Worker(Scanner_Input, Scanned_Item),
	runner:   ^thread.Thread,
	progress: Scanner_Progress,
}

@(private="file")
_accum_files :: proc(dir: string, output: ^[dynamic]os.File_Info, counter: ^int, allocator: mem.Allocator) -> os.Error {
	df := os.read_all_directory_by_path(dir, allocator) or_return
	defer delete(df)

	for file in df {
		if file.type == .Regular {
			append(output, file)
			sync.atomic_add(counter, 1)
		}
		else if file.type == .Directory {
			_accum_files(file.fullpath, output, counter, allocator)
		}
	}
	return nil
}

scanner_init :: proc(
	ts: ^Scanner,
	consume_proc: proc(data: rawptr, items: []Scanned_Item) -> Error,
	consume_data: rawptr,
) {
	_thread_proc :: proc(t: ^thread.Thread) {
		w := cast(^Scanner) t.data
		shared.worker_run(&w.worker)
	}

	_produce_proc :: proc(
		data:             rawptr,
		input:            []Scanner_Input,
		output_allocator: mem.Allocator,
	) -> (output: []Scanned_Item, error: shared.Error) {
		scratch: mem.Scratch
		mem.scratch_init(&scratch, 512<<10, context.allocator)
		defer mem.scratch_destroy(&scratch)

		context.allocator = mem.scratch_allocator(&scratch)

		progress := cast(^Scanner_Progress) data
		
		buf := make_dynamic_array_len_cap(
			[dynamic]Scanned_Item, 0, 4096,
			output_allocator
		)
		
		sync.atomic_store(&progress.scanned_items, 0)
		sync.atomic_store(&progress.total_items, len(input))
		sync.atomic_store(&progress.scanned_files, 0)
				
		process_file :: proc(
			progress:         ^Scanner_Progress,
			input:            Scanner_Input,
			output:           ^[dynamic]Scanned_Item,
			depth:            int,
			output_allocator: mem.Allocator,
		) -> shared.Error {
			image_formats := []string {
				".jpeg", ".jpg", ".png", ".bmp",
				".tga", ".webm"
			}

			file := os.open(input.path) or_return
			defer os.close(file)
			
			if os.is_dir(input.path) {
				iter := os.read_directory_iterator_create(file)
				defer os.read_directory_iterator_destroy(&iter)
				
				if depth != 0 do sync.atomic_add(&progress.total_items, 1)
				
				for file, _ in os.read_directory_iterator(&iter) {
					process_file(progress, Scanner_Input {
						path = file.fullpath,
						overwrite = input.overwrite,
					}, output, depth+1, output_allocator)
				}	

				sync.atomic_add(&progress.scanned_items, 1)
			}
			else {
				ext := filepath.ext(input.path)
				audio_format, is_audio := audio_file_format_from_extension(ext)

				if is_audio {
					track_data := read_tags(
						input.path, output_allocator
					) or_return

					s := Scanned_Item {
						variant = Scanned_Track {
							tags = track_data,
							url  = strings.concatenate({"file://", input.path}, output_allocator),
						},
						overwrite = input.overwrite,
					}

					s.overwrite = input.overwrite
										
					append(output, s)
				}
				else if slice.contains(image_formats, ext) {
					folder_name, _ := filepath.clean(filepath.dir(input.path), output_allocator)

					s := Scanned_Item {
						variant = Scanned_Art {
							folder = folder_name,
							image  = strings.clone(input.path, output_allocator),
						},
					}

					log.debug("Cover art", folder_name, s.variant.(Scanned_Art).image)

					s.overwrite = input.overwrite

					append(output, s)
				}
				else do return false

				sync.atomic_add(&progress.scanned_files, 1)
			}

			return nil
		}

		for item in input {
			process_file(progress, item, &buf, 0, output_allocator)
		}

		output = buf[:]
		return
	}

	_clone_proc :: proc(
		input: Scanner_Input, allocator: mem.Allocator
	) -> (out: Scanner_Input, error: mem.Allocator_Error) {
		out = input
		out.path = strings.clone(input.path,allocator)
		return
	}

	shared.worker_init(
		&ts.worker, _produce_proc, consume_proc, &ts.progress, consume_data,
		output_scratch_size = FILE_SCANNER_SCRATCH_SIZE,
		input_scratch_size  = 512<<10,
	)

	ts.worker.clone_input = _clone_proc

	ts.runner = thread.create(_thread_proc)
	ts.runner.data = ts
	ts.runner.init_context = context

	thread.start(ts.runner)
}

scanner_destroy :: proc(ts: ^Scanner) {
	shared.worker_destroy(&ts.worker, ts.runner)
}

scanner_queue :: proc(ts: ^Scanner, input: []Scanner_Input) {
	shared.worker_send_input(&ts.worker, input)
}

scanner_is_running :: proc(ts: ^Scanner) -> bool {
	return shared.worker_is_working(&ts.worker)
}

scanner_get_progress :: proc(
	ts: ^Scanner
) -> (scanned_dirs, total_dirs, scanned_files: int, running: bool) {
	if scanner_is_running(ts) {
		scanned_dirs = sync.atomic_load(&ts.progress.scanned_items)
		total_dirs = sync.atomic_load(&ts.progress.total_items)
		scanned_files = sync.atomic_load(&ts.progress.scanned_files)
		running = true
		return
	}
	
	return
}

scanner_make_input :: proc(paths: []string, overwrite: bool, allocator: mem.Allocator) -> []Scanner_Input {
	res := make([]Scanner_Input, len(paths), allocator)
	for &input, i in res {
		input.path = paths[i]
		input.overwrite = overwrite
	}

	return res
}

