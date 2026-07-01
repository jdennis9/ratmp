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

import "core:fmt"
import "core:testing"
import "core:sync"
import "core:mem"
import "core:thread"

Background_Task_Progress :: struct {
	items_processed: int,
	total_items:     int,
	current_stage:   string,
}

Background_Task_Proc :: #type proc(task: ^Background_Task) -> Error

Background_Task :: struct {
	progress:              Background_Task_Progress,
	data:                  rawptr,
	runner:                ^thread.Thread,
	// The task proc needs to signal this once input is consumed
	input_consumed_signal: sync.Auto_Reset_Event,
	run_proc:              Background_Task_Proc,
	scratch:               mem.Scratch,
	allocator:             mem.Allocator,
	want_cancel:           bool,
}

@(private="file")
_bgtask_thread_proc :: proc(t: ^thread.Thread) {
	data := cast(^Background_Task) t.data
	data.run_proc(auto_cast data)
}

bgtask_cancel :: proc(
	task: ^Background_Task,
) {
	if task.runner != nil {
		if !thread.is_done(task.runner) {
			task.want_cancel = true
			thread.join(task.runner)
		}
		thread.destroy(task.runner)
		task.runner = nil
		mem.scratch_destroy(&task.scratch)
	}
}

// Starts a task ands waits for input to be consumed
bgtask_run :: proc(
	task: ^Background_Task,
	run_proc: proc(task: ^Background_Task) -> Error,
	parent_allocator: mem.Allocator,
	data: rawptr,
	scratch_size := 64<<10,
) {
	bgtask_cancel(task)
	task.data                  = data
	task.runner                = thread.create(_bgtask_thread_proc)
	task.runner.init_context   = context
	task.runner.data           = task
	task.run_proc              = run_proc
	task.want_cancel           = false
	task.input_consumed_signal = {}

	mem.scratch_init(
		&task.scratch,
		scratch_size,
		parent_allocator,
	)

	task.allocator = mem.scratch_allocator(&task.scratch)
	
	thread.start(task.runner)

	sync.auto_reset_event_wait(&task.input_consumed_signal)
}

// Called by the task proc once input has been copied
bgtask_consume_input :: proc(task: ^Background_Task) {
	sync.auto_reset_event_signal(&task.input_consumed_signal)
}

bgtask_is_complete :: proc(
	task: ^Background_Task,
) -> bool {
	if task.runner == nil do return false
	return thread.is_done(task.runner)
}

bgtask_get_progress :: proc(
	task: ^Background_Task,
) -> (items_processed, total_items: int, is_running: bool) {
	if task.runner != nil {
		items_processed = sync.atomic_load(&task.progress.items_processed)
		total_items = sync.atomic_load(&task.progress.total_items)
		is_running = true
		return
	}

	return
}

@test
test_bgtask :: proc(t: ^testing.T) {
	task: Background_Task
	Data :: struct {x: int}

	data := Data{x = 100}

	task_proc :: proc(task: ^Background_Task) -> Error {
		data := cast(^Data) task.data
		fmt.println("x =", data.x)
		data.x = 1000
		return nil
	}

	bgtask_run(&task, task_proc, context.allocator, &data)
	bgtask_cancel(&task)
	testing.expect(t, data.x == 1000)
}
