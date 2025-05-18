package fftw

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "fftw3f.lib"
}
else {
	foreign import lib "system:fftw3f"
}

plan :: distinct rawptr
complex :: [2]f32

@(link_prefix="fftwf_")
foreign lib {
	/*
	input is size n
	output is size (n/2)+1
	*/
	plan_dft_r2c_1d :: proc(n: c.int, input: [^]f32, output: [^]complex, flags: c.uint) -> plan ---
	execute_dft_r2c :: proc(_: plan, input: [^]f32, output: [^]complex) ---
	execute :: proc(_: plan) ---
	destroy_plan :: proc(_: plan) ---
	cleanup :: proc() ---
}
