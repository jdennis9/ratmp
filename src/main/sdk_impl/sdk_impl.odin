package sdk_impl

import "core:mem"
import imgui "src:thirdparty/odin-imgui"
import lib "src:main/library"
import "src:sdk"

get_sdk :: proc() -> ^sdk.SDK {
	@static impl: sdk.SDK
	if impl.interface_version < 1 {
		impl = sdk.SDK {
			interface_version = 1,
			imgui_context     = imgui.GetCurrentContext(),

			find_track = proc(id: sdk.Track_ID) -> (t: sdk.Track, ok: bool) {
				native := lib.get_track(transmute(lib.Track_ID) id) or_return
				t = convert_track(native)
				ok = true
				return
			},

			get_all_track_ids = proc(allocator: mem.Allocator) -> []sdk.Track_ID {
				native := lib.get_all_track_ids(context.allocator)
				defer delete(native)
				if native == nil do return nil

				out := make([]sdk.Track_ID, len(native), allocator)
				for n, i in native {
					out[i] = transmute(sdk.Track_ID) n
				}

				return out
			}
		}
	}

	return &impl
}

convert_track :: proc(native: lib.Track) -> (t: sdk.Track) {
	t.url        = native.url
	t.title      = native.title
	t.artists    = native.artists
	t.genres     = native.genres
	t.album      = native.album
	t.bitrate    = auto_cast native.bitrate
	t.samplerate = auto_cast native.samplerate
	t.channels   = auto_cast native.channels
	return
}
