package dsp

import "core:math/linalg"

Filter_Band :: struct {
	center: f32,
	width: f32,
	gain: f32,
}

Filter_State :: struct {
	last_input: [dynamic]f32,
	last_output: [dynamic]f32,
}

filter_band_coeffs :: proc(fb: Filter_Band, samplerate: f32) -> (a: [3]f32, b: [3]f32) {
	sq :: proc(x: f32) -> f32 {return x * x}

	fs := samplerate
	GB := linalg.pow(f32(10), 9 / 20)
	G0: f32 = 1
	G := linalg.pow(f32(10), fb.gain / 20)
	Bf := fb.width
	f0 := fb.center

	beta := linalg.tan(Bf / 2 * linalg.PI / (fs / 2)) *
		linalg.sqrt(
			abs(sq(GB)) - sq(G0) / linalg.sqrt(abs(sq(G) - sq(GB)))
		)

	b[0] = (G0 + G * beta) / (1 + beta)
	b[1] = -2 * G0 * linalg.cos(f0 * linalg.PI / (fs/2)) / (1 + beta)
	b[2] = (G0 - G * beta) / (1 + beta)

	a[0] = 1
	a[1] = -2 * linalg.cos(f0 * linalg.PI / (fs/2)) / (1 + beta)
	a[2] = (1 - beta) / (1 + beta)
	
	return
}

filter_reset :: proc(state: ^Filter_State) {
	clear(&state.last_input)
	clear(&state.last_output)
}

filter_apply :: proc(
	state: ^Filter_State, bands: []Filter_Band,
	input: []f32, output: []f32,
	samplerate: f32
) {
	x := input
	y := output

	assert(len(x) == len(y))

	if len(state.last_output) != len(y) do resize(&state.last_output, len(y))
	if len(state.last_input) != len(x) do resize(&state.last_input, len(x))

	x_past := state.last_input[:]
	y_past := state.last_output[:]

	for band in bands {
		a, b := filter_band_coeffs(band, samplerate)
		order := len(a) - 1

		for i in 0..<order {
			y[i] = 0

			for j in 0..<order+1 {
				if i - j < 0 {
					y[i] += b[j] * x_past[len(x_past) - j]
				}
				else {
					y[i] += b[j] * x[i - j]
				}
			}

			for j in 0..<order {
				if i - j - 1 < 0 {
					y[i] -= a[j + 1] * y_past[len(y_past) - j - 1]
				}
				else {
					y[i] -= a[j + 1] * y[i - j - 1]
				}
			}
		}

		for i in order..<len(x) {
			y[i] = 0
			
			for j in 0..<order+1 {
				y[i] += b[j] * x[i - j]
			}

			for j in 0..<order {
				y[i] -= a[j + 1] * y[i - j - 1]
			}

			y[i] /= a[0]
		}
	}
	
	copy(x_past, x)
	copy(y_past, y)
}
