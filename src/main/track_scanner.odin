package main

import "core:log"
import "core:testing"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:sync"
import "core:mem"
import "core:thread"
import "core:os"

TRACK_SCANNER_SCRATCH_SIZE :: (32<<10)

Track_Scanner_Input :: struct {
	path: string,
	overwrite: bool,
}

Track_Scanner_Progress :: struct {
	scanned_items, total_items, scanned_files: int,
}

Track_Scanner :: struct {
	worker:   Worker(Track_Scanner_Input, Track_Data),
	runner:   ^thread.Thread,
	progress: Track_Scanner_Progress,
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

track_scanner_init :: proc(
	ts: ^Track_Scanner,
	consume_proc: proc(data: rawptr, tracks: []Track_Data) -> Error,
	consume_data: rawptr,
) {
	_thread_proc :: proc(t: ^thread.Thread) {
		w := cast(^Track_Scanner) t.data
		worker_run(&w.worker)
	}

	_produce_proc :: proc(
		data: rawptr,
		input: []Track_Scanner_Input,
		output_allocator: mem.Allocator,
	) -> (output: []Track_Data, error: Error) {
		scratch: mem.Scratch
		mem.scratch_init(&scratch, 256<<10, context.allocator)
		defer mem.scratch_destroy(&scratch)

		context.allocator = mem.scratch_allocator(&scratch)

		progress := cast(^Track_Scanner_Progress) data
		
		buf := make_dynamic_array_len_cap(
			[dynamic]Track_Data, 0, 4096,
			output_allocator
		)
		
		sync.atomic_store(&progress.scanned_items, 0)
		sync.atomic_store(&progress.total_items, len(input))
		sync.atomic_store(&progress.scanned_files, 0)
				
		process_file :: proc(
			progress: ^Track_Scanner_Progress,
			input: Track_Scanner_Input,
			output: ^[dynamic]Track_Data,
			depth: int,
			output_allocator: mem.Allocator,
		) -> Error {
			file := os.open(input.path) or_return
			defer os.close(file)
			
			if os.is_dir(input.path) {
				iter := os.read_directory_iterator_create(file)
				defer os.read_directory_iterator_destroy(&iter)
				
				if depth != 0 do sync.atomic_add(&progress.total_items, 1)
				
				for file, _ in os.read_directory_iterator(&iter) {
					process_file(progress, Track_Scanner_Input {
						path = file.fullpath,
						overwrite = true
					}, output, depth+1, output_allocator)
				}	

				sync.atomic_add(&progress.scanned_items, 1)
			}
			else {
				track_data := read_audio_file_metadata(
					input.path, output_allocator
				) or_return
				
				if input.overwrite do track_data.flags |= {.Overwrite}
				
				append(output, track_data)
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
		input: Track_Scanner_Input, allocator: mem.Allocator
	) -> (out: Track_Scanner_Input, error: mem.Allocator_Error) {
		out = input
		out.path = strings.clone(input.path,allocator)
		return
	}

	worker_init(
		&ts.worker, _produce_proc, consume_proc, &ts.progress, consume_data,
		output_scratch_size = TRACK_SCANNER_SCRATCH_SIZE,
		input_scratch_size = 32<<10,
	)

	ts.worker.clone_input = _clone_proc

	ts.runner = thread.create(_thread_proc)
	ts.runner.data = ts
	ts.runner.init_context = context

	thread.start(ts.runner)
}

track_scanner_destroy :: proc(ts: ^Track_Scanner) {
	worker_destroy(&ts.worker, ts.runner)
}

track_scanner_queue :: proc(ts: ^Track_Scanner, input: []Track_Scanner_Input) {
	worker_send_input(&ts.worker, input)
}

track_scanner_is_running :: proc(ts: ^Track_Scanner) -> bool {
	return worker_is_working(&ts.worker)
}

track_scanner_get_progress :: proc(
	ts: ^Track_Scanner
) -> (scanned_dirs, total_dirs, scanned_files: int, running: bool) {
	if track_scanner_is_running(ts) {
		scanned_dirs = sync.atomic_load(&ts.progress.scanned_items)
		total_dirs = sync.atomic_load(&ts.progress.total_items)
		scanned_files = sync.atomic_load(&ts.progress.scanned_files)
		running = true
		return
	}
	
	return
}

@test
test_track_scanner :: proc(t: ^testing.T) {
	ts: Track_Scanner
	done_signal: sync.Auto_Reset_Event

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	consume_proc :: proc(_: rawptr, tracks: []Track_Data) -> Error {return nil}

	track_scanner_init(&ts, consume_proc, nil)
	defer track_scanner_destroy(&ts)

	ts.worker.processing_done_signal = &done_signal

	track_scanner_queue(&ts, {{path = "D:\\Media\\Music"}})
	sync.auto_reset_event_wait(&done_signal)
}
