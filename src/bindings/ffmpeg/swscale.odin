package ffmpeg

import "core:c"

foreign import lib "swscale.lib"


SwsContext :: struct {}
SwsFilter :: struct {}

foreign lib {
	sws_alloc_context :: proc() -> ^SwsContext ---
	sws_freeContext :: proc(ctx: ^SwsContext) ---
	sws_init_context :: proc(ctx: ^SwsContext, srcFilter: ^SwsFilter, dstFilter: ^SwsFilter) -> c.int ---
	sws_getContext :: proc(
		srcW: c.int, srcH: c.int, srcFormat: PixelFormat,
		dstW: c.int, dstH: c.int, dstFormat: PixelFormat,
		flags: c.int, srcFilter: ^SwsFilter = nil, dstFilter: ^SwsFilter = nil,
		param: ^f64 = nil,
	) -> ^SwsContext ---

	sws_scale_frame :: proc(ctx: ^SwsContext, dst: ^Frame, src: ^Frame) -> c.int ---
}
