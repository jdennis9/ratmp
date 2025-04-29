package kissfft

import "core:c"
import "core:c/libc"

when ODIN_OS == .Windows {
	foreign import lib "kissfft-float.lib"
}
else {
	foreign import lib "system:kissfft-float"
}

fftr_cfg :: distinct rawptr
fft_cpx :: struct {r, i: f32}

@(link_prefix="kiss_")
foreign lib {
	fftr_alloc :: proc(nfft: c.int, inverse_fft: c.int, mem: rawptr, lenmem: ^c.size_t) -> fftr_cfg ---
	fftr :: proc(cfg: fftr_cfg, timedata: [^]f32, freqdata: [^]fft_cpx) ---
}

fftr_free :: proc(cfg: fftr_cfg) {
	libc.free(cfg)
}
