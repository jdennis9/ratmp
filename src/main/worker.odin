package main

import "core:time"
import "core:fmt"
import "core:thread"
import "core:log"
import "core:slice"
import "core:testing"
import "core:sync"
import "core:mem"

// =============================================================================
// Helpers for a background thread that is tasked with processing some input data
// which is consumed by another thread
// =============================================================================

Worker_Progress :: struct {
	processed_items: int,
	total_items: int,
}

Worker :: struct($IN: typeid, $OUT: typeid) {
	input_lock:             sync.Mutex,
	input:                  [dynamic]IN,
	output:                 [dynamic]OUT,
	// Supplied by owner. Signaled when there is output available
	processing_done_signal: ^sync.Auto_Reset_Event,
	output_consumed_signal: sync.Auto_Reset_Event,
	input_ready_signal:     sync.Auto_Reset_Event,
	input_consumed_signal:  sync.Auto_Reset_Event,
	should_close:           bool,
	is_processing:          bool,
	produce_data:           rawptr,
	consume_data:           rawptr,
	// Cleared when input is consumed.
	// The input array doesn't use this, only
	// the actual data contained in the array.
	// This is passed to the optional clone_input proc
	input_scratch:          mem.Scratch,

	produce: proc(data: rawptr, input: []IN, output_allocator: mem.Allocator) -> ([]OUT, Error),
	consume: proc(data: rawptr, output: []OUT) -> Error,
	clone_input: proc(input: IN, allocator: mem.Allocator) -> (IN, mem.Allocator_Error),
}

worker_init :: proc(
	w: ^Worker($IN, $OUT),
	produce_proc: proc(data: rawptr, input: []IN,  output_allocator: mem.Allocator) -> ([]OUT, Error),
	consume_proc: proc(data: rawptr, output: []OUT) -> Error,
	produce_data: rawptr,
	consume_data: rawptr,
	output_scratch_size := 64<<10,
	input_scratch_size := 0,
) {
	w.consume = consume_proc
	w.produce = produce_proc
	w.produce_data = produce_data
	w.consume_data = consume_data

	if input_scratch_size != 0 {
		mem.scratch_init(&w.input_scratch, input_scratch_size)
	}
}

worker_destroy :: proc(w: ^Worker($IN, $OUT), runner: ^thread.Thread) {
	if runner != nil {
		sync.atomic_store(&w.should_close, true)
		sync.auto_reset_event_signal(&w.input_ready_signal)

		thread.join(runner)
		thread.destroy(runner)
	}

	delete(w.input)
	delete(w.output)

	if w.input_scratch.data != nil {
		mem.scratch_destroy(&w.input_scratch)
	}	
}

// This should be called on a background thread
worker_run :: proc(w: ^Worker($IN, $OUT)) {
	output_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&output_arena)
	defer mem.dynamic_arena_destroy(&output_arena)
	output_allocator := mem.dynamic_arena_allocator(&output_arena)

	for !sync.atomic_load(&w.should_close) {
		input: []IN

		sync.auto_reset_event_wait(&w.input_ready_signal)
		
		// -----------------------------------------------------------------------
		// Prepare input
		// -----------------------------------------------------------------------
		sync.lock(&w.input_lock)
		input = slice.clone(w.input[:])
		clear(&w.input)
		mem.scratch_free_all(&w.input_scratch)
		sync.unlock(&w.input_lock)

		// -----------------------------------------------------------------------------
		// []IN -> []OUT
		// -----------------------------------------------------------------------------
		sync.atomic_store(&w.is_processing, true)
		output := w.produce(w.produce_data, input, output_allocator) or_continue
		sync.atomic_store(&w.is_processing, false)

		if w.processing_done_signal != nil {
			sync.auto_reset_event_signal(w.processing_done_signal)
		}

		// -----------------------------------------------------------------------
		// Consume output
		// -----------------------------------------------------------------------
		w.consume(w.consume_data, output)

		mem.dynamic_arena_free_all(&output_arena)
	}

	fmt.println("Closing")

	return
}

worker_send_input :: proc(w: ^Worker($IN, $OUT), input: []IN) {
	sync.lock(&w.input_lock)
	if w.clone_input != nil {
		assert(w.input_scratch.data != nil)
		allocator := mem.scratch_allocator(&w.input_scratch)
		for i in input do append(&w.input, w.clone_input(i, allocator) or_continue)
	}
	else {
		for i in input do append(&w.input, i)
	}

	sync.unlock(&w.input_lock)
	sync.auto_reset_event_signal(&w.input_ready_signal)
}

worker_is_working :: proc(w: ^Worker($IN, $OUT)) -> bool {
	return sync.atomic_load(&w.is_processing)
}

@test
test_worker :: proc(t: ^testing.T) {
	w: Worker(int, int)
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	_thread_proc :: proc(t: ^thread.Thread) {
		w := cast(^Worker(int, int)) t.data
		worker_run(w)
	}
	
	produce_proc :: proc(
		_: rawptr, input: []int, allocator: mem.Allocator
	) -> (output: []int, error: Error) {
		output = slice.clone(input, allocator)
		for &o in output do o += 1
		return
	}
	
	consume_proc :: proc(
		_: rawptr, output: []int,
	) -> Error {
		fmt.println("Consoom", output)
		return nil
	}
	
	thr := thread.create(_thread_proc)
	
	worker_init(&w, produce_proc, consume_proc, nil, nil)
	defer {
		fmt.println("CLOSE")
		worker_destroy(&w, thr)
	}
	
	thr.data = &w
	thr.init_context = context
	thread.start(thr)
	
	worker_send_input(&w, []int{1, 2, 3, 4, 5, 6, 7, 8})
	fmt.println("GSDGSSGDSGSDGSGDGDGSSSSSSSSSSSSSSSSSSSSSSSSSSS")
	time.sleep(time.Second * 4)
}
