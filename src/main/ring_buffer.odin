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

import "core:mem"
import "core:slice"
import "core:sync"


@(private="file")
_wrap :: proc(i, N: int) -> int {
	/*if i < 0 do return N+i
	else if i == 0 do return 0
	else do return i - ((i/N)*N)*/
	/*if i >= 0 && i < N do return i
	else if i < 0 do return N+i
	else if i >= N do return i - ((i/N)*N)*/
	return i % N
}

Ring_Buffer :: struct($T: typeid) {
	data: []T,
	producer_index: int,
	consumer_index: int,
	allocator: mem.Allocator,
}

rb_init :: proc(buf: ^Ring_Buffer($T), size: int, allocator: mem.Allocator) {
	//buf.consumer_index = size-1
	buf.consumer_index = 0
	buf.producer_index = 0
	buf.allocator = allocator
	buf.data = make([]T, size, allocator)
}

rb_resize :: proc(buf: ^Ring_Buffer($T), size: int) {
	delete(buf.data, buf.allocator)
	buf.data = make([]T, size, buf.allocator)
	rb_reset(buf)
}

rb_reset :: proc(buf: ^Ring_Buffer($T)) {
	slice.zero(buf.data)
	buf.producer_index = 0
	buf.consumer_index = 0
}

rb_space :: proc(buf: Ring_Buffer($T)) -> int {
	write_end := _wrap(buf.consumer_index-1, len(buf.data))
	if write_end >= buf.producer_index do return write_end - buf.producer_index
	else do return (len(buf.data) - buf.producer_index) + write_end
}

rb_produce :: proc(buf: ^Ring_Buffer($T), data: []T, loc := #caller_location) -> (copied: int) {
	buf_size := len(buf.data)
	if buf_size == 0 do return
	producer := sync.atomic_load(&buf.producer_index)

	write_end := _wrap(producer-1, buf_size)

	if producer > write_end {
		copied += copy(buf.data[producer:], data[:])
		if copied < len(data) {
			copied += copy(buf.data[:write_end], data[copied:])
		}
	}
	else {
		copied += copy(buf.data[producer:write_end], data[:])
	}
	
	sync.atomic_store(&buf.producer_index, _wrap(producer + copied, buf_size))

	return
}

// Fills the output buffer as much as possible, then consumes consume_count elements
rb_consume :: proc(buf: ^Ring_Buffer($T), output: []T, consume_count: Maybe(int), loc := #caller_location) -> (copied: int) {
	buf_size := len(buf.data)
	if buf_size == 0 do return
	producer := sync.atomic_load(&buf.producer_index)
	consumer := sync.atomic_load(&buf.consumer_index)
	read_end := producer
	
	if read_end < consumer {
		copied += copy(output[:], buf.data[consumer:])
		if copied < len(output) {
			copied += copy(output[copied:], buf.data[:read_end])
		}
	}
	else {
		copied += copy(output[:], buf.data[consumer:read_end])
	}
	
	consumer += consume_count.? or_else copied
	consumer = _wrap(consumer, buf_size)
	sync.atomic_store(&buf.consumer_index, consumer)

	return
}

rb_destroy :: proc(buf: ^Ring_Buffer($T)) {
	delete(buf.data)
	buf.data = nil
}

import "core:testing"
import "core:fmt"

@test
test_ring_buffer :: proc(t: ^testing.T) {
	buf: Ring_Buffer(f32)
	rb_init(&buf, 16, context.allocator)
	defer rb_destroy(&buf)

	for i in 0..<32 {
		b := f32(i*8)
		v := []f32{b+1, b+2, b+3, b+4, b+5, b+6, b+7, b+8}
		rb_produce(&buf, v)
		rb_consume(&buf, v, 5)
		fmt.println("prod", buf.data)
		fmt.println("con", v)
	}
}
