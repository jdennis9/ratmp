/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

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
package util

import "core:sync"

Ring_Buffer :: struct($T: typeid, $SIZE: uint) {
	data: [SIZE]T,
	producer_index: int,
	consumer_index: int,
}

@(private="file")
_wrap :: proc(i, N: int) -> int {
	return i - ((i/N)*N)
}

rb_init :: proc(buf: ^Ring_Buffer($T, $SIZE)) {
	buf.consumer_index = 0
	buf.consumer_index = 0
}

rb_reset :: proc(buf: ^Ring_Buffer($T, $SIZE)) {
	rb_init(buf)
	buf.producer_index = 0
}

rb_produce :: proc(buf: ^Ring_Buffer($T, $SIZE), data: []T, stride := 1, offset := 0) {
	for i := 0; i < len(data); i += stride {
		if (buf.producer_index + 1) % int(SIZE) == buf.consumer_index {
			return
		}

		buf.data[buf.producer_index] = data[i+offset]
		buf.producer_index += 1
		buf.producer_index = _wrap(buf.producer_index, int(SIZE))
	}
}

// Fills the output buffer as much as possible, then consumes consume_count elements
rb_consume :: proc(buf: ^Ring_Buffer($T, $SIZE), output: []T, consume_count: int) -> (elems_copied: int) {
	copied := 0
	producer := sync.atomic_load(&buf.producer_index)
	consumer := sync.atomic_load(&buf.consumer_index)

	if producer < consumer {
		copied = copy(output[:], buf.data[consumer:int(SIZE)])
	}
	else {
		copied = copy(output[:], buf.data[consumer:producer])
	}

	left_over := len(output) - copied
	if left_over > 0 {
		copy(output[copied:], buf.data[0:min(left_over, producer)])
	}

	consumer += consume_count
	consumer = _wrap(consumer, int(SIZE))
	sync.atomic_store(&buf.consumer_index, consumer)

	return
}

rb_destroy :: proc(buf: ^Ring_Buffer($T, $SIZE)) {
}

import "core:testing"
import "core:fmt"

@test
test_ring_buffer :: proc(t: ^testing.T) {
	buf: Ring_Buffer(f32, 16)
	rb_init(&buf)
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
