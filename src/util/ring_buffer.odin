package util

import "core:sync"
import "core:slice"

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

rb_produce :: proc(buf: ^Ring_Buffer($T, $SIZE), data: []f32, stride := 1, offset := 0) {
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
rb_consume :: proc(buf: ^Ring_Buffer($T, $SIZE), output: []f32, consume_count: int) -> (elems_copied: int) {
	for i in 0..<len(output) {
		n := _wrap(buf.consumer_index+i, int(SIZE))
		if n == buf.producer_index {break}
		output[i] = buf.data[n]
		elems_copied += 1
	}
	buf.consumer_index += consume_count
	buf.consumer_index = _wrap(buf.consumer_index, int(SIZE))
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
