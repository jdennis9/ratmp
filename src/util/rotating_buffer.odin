package util

import "core:math"
import "core:slice"

Rotating_Buffer :: struct($T: typeid, $N: uint) where N > 1 {
	data: [dynamic]T,
	sizes: [N]int,
	push_index: uint,
}

rotating_buffer_init :: proc(buffer: ^Rotating_Buffer($T, $N)) {
}

rotating_buffer_destroy :: proc(buffer: ^Rotating_Buffer($T, $N)) {
	delete(buffer.data)
	buffer.data = nil
	buffer.push_index = 0
}

rotating_buffer_reset :: proc(buffer: ^Rotating_Buffer($T, $N)) {
	clear(&buffer.data)
	for &s in buffer.sizes {s = 0}
	buffer.push_index = 0
}

rotating_buffer_push :: proc(b: ^Rotating_Buffer($T, $N), data: []T) {
	if b.push_index < N {
		for e in data {
			append(&b.data, e)
		}

		b.sizes[b.push_index] = len(data)
	}
	else {
		index := N-1

		slice.rotate_left(b.data[:], b.sizes[0])
		copy(b.sizes[:], b.sizes[1:])

		resize(&b.data, math.sum(b.sizes[:N-1]))

		for e in data {
			append(&b.data, e)
		}

		b.sizes[index] = len(data)
	}
	

	b.push_index += 1
}

import "core:testing"
import "core:fmt"

@test
test_rotating_buffer :: proc(t: ^testing.T) {
	buf: Rotating_Buffer(f32, 2)
	rotating_buffer_init(&buf)
	defer rotating_buffer_destroy(&buf)

	rotating_buffer_push(&buf, []f32{1, 2, 3})
	testing.expect(t, len(buf.data) == 3 && buf.sizes[0] == 3)
	rotating_buffer_push(&buf, []f32{1, 2, 3, 4})
	testing.expect(t, buf.sizes[1] == 4)

	rotating_buffer_push(&buf, []f32{1, 2, 3, 4, 5})
	testing.expect(t, buf.sizes[0] == 4)
	testing.expect(t, buf.sizes[1] == 5)

	rotating_buffer_push(&buf, []f32{1, 2, 3, 4, 5, 6})
	testing.expect(t, buf.sizes[0] == 5)
	testing.expect(t, buf.sizes[1] == 6)

	rotating_buffer_reset(&buf)

	for i in 0..<5 {
		f: []f32 = {f32(i)*3+1, f32(i)*3+2, f32(i)*3+3}
		rotating_buffer_push(&buf, f)
		fmt.println(buf.data)
	}
}
