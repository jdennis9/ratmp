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
package shared

import "core:sync"
import "core:mem"
import "core:container/queue"

Event_Queue :: struct($T: typeid) {
	events:          queue.Queue(T),
	event_allocator: mem.Allocator, // Memory is freed when events are processed
	event_arena:     mem.Dynamic_Arena,
	lock:            sync.Mutex,
	wake_proc:       proc(),
	signal:          sync.Auto_Reset_Event,
}

event_queue_init :: proc(eq: ^Event_Queue($T)) {	
	mem.dynamic_arena_init(&eq.event_arena)
	eq.event_allocator = mem.dynamic_arena_allocator(&eq.event_arena)
}

event_queue_destroy :: proc(eq: ^Event_Queue($T)) {
	mem.dynamic_arena_destroy(&eq.event_arena)
}

event_queue_wait :: proc(eq: ^Event_Queue($T)) {
	sync.auto_reset_event_wait(&eq.signal)
}

event_queue_wake :: proc(eq: ^Event_Queue($T)) {
	sync.auto_reset_event_signal(&eq.signal)
	if eq.wake_proc != nil do eq.wake_proc()
}

event_queue_send :: proc(eq: ^Event_Queue($T), evt: T) {
	sync.guard(&eq.lock)
	queue.append(&eq.events, evt)
	event_queue_wake(eq)
}

event_queue_get :: proc(eq: ^Event_Queue($T)) -> (evt: T, have_evt: bool) {
	sync.guard(&eq.lock)
	return queue.pop_back_safe(&eq.events)
}
