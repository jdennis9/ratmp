package util

import "core:sync"
import "core:slice"

Ring_Buffer :: struct($T: typeid, $SIZE: uint) {
	data: [SIZE]T,
	producer_index: int,
	consumer_index: int,
}

rb_init :: proc(buf: ^Ring_Buffer($T, $SIZE)) {
}

rb_reset :: proc(buf: ^Ring_Buffer($T, $SIZE)) {
}

rb_produce :: proc(buf: ^Ring_Buffer($T, $SIZE), data: []f32, stride := 1, offset := 0) {
}

// Fills the output buffer as much as possible, then consumes consume_count elements
rb_consume :: proc(buf: ^Ring_Buffer($T, $SIZE), output: []f32, consume_count: int) -> (elems_copied: int) {
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
}
