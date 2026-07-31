package client

when ODIN_OS == .Windows {
	@require foreign import "../../../lib/freetype.lib"
	@require foreign import "../../../lib/brotlidec.lib"
	@require foreign import "../../../lib/brotlicommon.lib"
	@require foreign import "../../../lib/bz2.lib"
}
else {
	@require foreign import "system:freetype"
}
