package export_tracks_plugin

import "core:fmt"
import "../../src/sdk"
import imgui "src:thirdparty/odin-imgui"

rat: ^sdk.SDK

@(export, link_name="RATMP_load_plugin")
query_my_plugin :: proc(s: ^sdk.SDK) -> sdk.Plugin_Info {
	rat = s
	imgui.SetCurrentContext(auto_cast s.imgui_context)
	return sdk.Plugin_Info {
		display_name = "My Plugin",
		id_name      = "my_plugin",
		author       = "Me",
		version      = {1, 0, 0},
	}
}

@(export, link_name="RATMP_show_ui")
show_ui :: proc() {
	if imgui.Begin("My Plugin") {
		imgui.Text("Text to confirm my plugin is working")

		if imgui.Button("Dump tracks") {
			tracks := rat.get_all_track_ids(context.allocator)
			defer delete(tracks)

			for track_id in tracks {
				track := rat.find_track(track_id) or_continue
				fmt.println(track.url)
			}
		}
	}

	imgui.End()
}
