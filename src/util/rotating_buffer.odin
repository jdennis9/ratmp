package util

import "core:time"

Rotating_Buffer :: struct($T: typeid, $N: uint) where N > 1 {
	data: [dynamic]T,
	sizes: [N]int,
	timestamps: [N]time.Tick,
	push_index: int,
	max_block: int,
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

rotating_buffer_push :: proc(b: ^Rotating_Buffer($T, $N), data: []T, timestamp: time.Tick) {
	if b.push_index < auto_cast N {
		for e in data {
			append(&b.data, e)
		}

		b.sizes[b.push_index] = len(data)
		b.timestamps[b.push_index] = timestamp
		b.max_block = b.push_index
	}
	else {
		index := int(N-1)

		slice.rotate_left(b.data[:], b.sizes[0])
		//copy(b.sizes[:], b.sizes[1:])
		//copy(b.timestamps[:], b.timestamps[1:])
		slice.rotate_left(b.sizes[:], 1)
		slice.rotate_left(b.timestamps[:], 1)

		resize(&b.data, math.sum(b.sizes[:N-1]))

		for e in data {
			append(&b.data, e)
		}

		b.sizes[index] = len(data)
		b.timestamps[index] = timestamp
		b.max_block = index
	}

	b.push_index += 1
}

/*import "core:testing"
import "core:fmt"

@test
test_rotating_buffer :: proc(t: ^testing.T) {
	buf: Rotating_Buffer(f32, 3)
	rotating_buffer_init(&buf)
	defer rotating_buffer_destroy(&buf)

	rotating_buffer_push(&buf, []f32{1, 2, 3}, time.tick_now())
	fmt.println(buf.data)
	testing.expect(t, len(buf.data) == 3 && buf.sizes[0] == 3)
	rotating_buffer_push(&buf, []f32{1, 2, 3, 4}, time.tick_now())
	fmt.println(buf.data)
	testing.expect(t, buf.sizes[1] == 4)

	rotating_buffer_push(&buf, []f32{1, 2, 3, 4, 5}, time.tick_now())
	fmt.println(buf.data)
	testing.expect(t, buf.sizes[0] == 3)
	testing.expect(t, buf.sizes[1] == 4)
	testing.expect(t, buf.sizes[2] == 5)

	rotating_buffer_push(&buf, []f32{1, 2, 3, 4, 5, 6}, time.tick_now())
	fmt.println(buf.data)

	rotating_buffer_push(&buf, []f32{1, 2, 3, 4, 5, 6, 7}, time.tick_now())
	fmt.println(buf.data)

	/*rotating_buffer_push(&buf, []f32{1, 2, 3, 4, 5, 6})
	testing.expect(t, buf.sizes[0] == 5)
	testing.expect(t, buf.sizes[1] == 6)

	rotating_buffer_reset(&buf)

	for i in 0..<5 {
		f: []f32 = {f32(i)*3+1, f32(i)*3+2, f32(i)*3+3}
		rotating_buffer_push(&buf, f)
		fmt.println(buf.data)
	}*/
}*/
