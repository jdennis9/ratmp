package client

import "core:slice"
import "core:mem"
import "src:sdk"
import lib "src:main/library"

add_sdk_impl_procs :: proc(s: ^sdk.SDK) {
	s.get_clipboard_tracks = proc(allocator: mem.Allocator) -> []sdk.Track_ID {
		assert(size_of(lib.Track_ID) == size_of(sdk.Track_ID))
		tracks := ui_get_copied_tracks()
		if len(tracks) == 0 do return nil

		return transmute([]sdk.Track_ID) slice.clone(tracks, allocator)
	}
}
