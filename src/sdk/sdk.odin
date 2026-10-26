package sdk

import "core:mem"

// -----------------------------------------------------------------------------
// Plugin SDK exposed to plugin developers
// -----------------------------------------------------------------------------


/*
EXAMPLE PLUGIN:

import "path/to/imgui"
import "path/to/sdk"

show_ui :: proc() {
}

@(export, link_name="RATMP_load_plugin")
load_my_plugin :: proc(s: ^sdk.SDK) -> sdk.Plugin_Info {
	imgui.SetCurrentContext(s.imgui_context)
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
		imgui.Text("Hello, RATMP!")
	}
	imgui.End()

	return
}
*/

Version :: struct {major, minor, patch: int}

Plugin_Info :: struct {
	display_name: string,
	id_name:      string,
	author:       string,
	version:      Version,
	requires:     []string, // List of plugin identifiers (their id_name values)
}

Track_ID  :: distinct u32
Artist_ID :: i16
Genre_ID  :: i16
Album_ID  :: i16

Track :: struct {
	url:        string,
	title:      string,
	artists:    []Artist_ID,
	genres:     []Genre_ID,
	album:      Maybe(Album_ID),
	bitrate:    int,
	samplerate: int,
	channels:   int,
}

SDK :: struct {
	interface_version: u32,
	imgui_context:     rawptr,
	
	find_track:        proc(id: Track_ID) -> (Track, bool),
	get_all_track_ids: proc(allocator: mem.Allocator) -> []Track_ID,
}
