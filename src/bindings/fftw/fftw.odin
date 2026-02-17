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

R2R_Kind :: enum c.int {
	R2HC=0,
	HC2R=1,
	DHT=2,
    REDFT00=3,
	REDFT01=4,
	REDFT10=5,
	REDFT11=6,
    RODFT00=7,
	RODFT01=8,
	RODFT10=9,
	RODFT11=10
}

FLAG_PRESERVE_INPUT :: 1 << 4
FLAG_ESTIMATE :: 1 << 6

@(link_prefix="fftwf_")
foreign lib {
	/*
	input is size n
	output is size (n/2)+1
	*/
	plan_dft_r2c_1d :: proc(
		n: c.int, input: [^]f32, output: [^]complex, flags: c.uint = FLAG_PRESERVE_INPUT|FLAG_ESTIMATE
	) -> plan ---
	execute_dft_r2c :: proc(_: plan, input: [^]f32, output: [^]complex) ---
	plan_dft_c2r_1d :: proc(
		n: c.int, input: [^]complex, output: [^]f32, flags: c.uint = FLAG_PRESERVE_INPUT|FLAG_ESTIMATE
	) -> plan ---
	execute_dft_c2r :: proc(_: plan, input: [^]complex, output: [^]f32) ---
	execute :: proc(_: plan) ---
	destroy_plan :: proc(_: plan) ---
	cleanup :: proc() ---
}