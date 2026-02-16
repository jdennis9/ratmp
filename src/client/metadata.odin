/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
#+private
package client

import "core:strconv"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:os/os2"
import "core:slice"
import "core:log"

import stbi "vendor:stb/image"

import imgui "src:thirdparty/odin-imgui"

import "src:server"
import "src:sys"
import "src:decoder"

import "imx"

_load_track_album_art :: proc(lib: server.Library, track_id: Track_ID) -> (width, height: int, texture: imgui.TextureID, ok: bool) {
	file_data := server.library_find_track_cover_art(lib, track_id, context.allocator) or_return
	w, h: i32

	pixel_data := stbi.load_from_memory(raw_data(file_data), auto_cast len(file_data), &w, &h, nil, 4)
	if pixel_data == nil do return
	defer stbi.image_free(pixel_data)

	width = auto_cast w
	height = auto_cast h
	texture = sys.video_create_texture(pixel_data, width, height) or_return
	ok = true

	return
}

Metadata_Window :: struct {
	using base: Window_Base,
	track_id: Track_ID,
	displayed_track_id: Track_ID,
	album_art: imgui.TextureID,
	album_art_ratio: f32,
	album_art_size: [2]f32,
	file_info: os2.File_Info,
	crop_album_art: bool,
}

METADATA_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Metadata",
	internal_name = WINDOW_METADATA,
	make_instance = metadata_window_make_instance_proc,
	show = metadata_window_show_proc,
	hide = metadata_window_hide_proc,
	configure = metadata_window_configure_proc,
	save_config = metadata_window_save_config_proc,
	flags = {.DefaultShow},
}

METADATA_POPUP_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Track Metadata",
	internal_name = WINDOW_METADATA_POPUP,
	make_instance = metadata_window_make_instance_proc,
	show = metadata_window_show_proc,
	hide = metadata_window_hide_proc,
	configure = metadata_window_configure_proc,
	save_config = metadata_window_save_config_proc,
	flags = {.NoInitialInstance},
}

metadata_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	win := new(Metadata_Window, allocator)
	win.imgui_flags = {.AlwaysVerticalScrollbar}
	return win
}

metadata_window_configure_proc :: proc(self: ^Window_Base, key, value: string) {
	state := cast(^Metadata_Window) self

	if key == "CropAlbumArt" {
		if parsed, ok := strconv.parse_int(value); ok {
			state.crop_album_art = parsed > 0
		}
	}
}

metadata_window_save_config_proc :: proc(self: ^Window_Base, out_buf: ^imgui.TextBuffer) {
	state := cast(^Metadata_Window) self
	imgui.TextBuffer_appendf(out_buf, "CropAlbumArt=%d\n", i32(state.crop_album_art))
}

metadata_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Metadata_Window) self
	metadata_window_show(state, cl, sv)
}

metadata_window_show :: proc(
	state: ^Metadata_Window, cl: ^Client, sv: ^Server,
) -> (ok: bool) {
	if state.track_id != state.displayed_track_id {
		width, height: int
		have_art: bool

		state.displayed_track_id = state.track_id

		sys.video_destroy_texture(state.album_art)
		state.album_art = 0
		
		if state.track_id == 0 {
			return
		}
		
		path_buf: Path
		track_path := server.library_find_track_path(sv.library, path_buf[:], state.track_id) or_return
		width, height, state.album_art, have_art = _load_track_album_art(sv.library, state.track_id)

		if have_art {
			state.album_art_ratio = f32(height) / f32(width)
			state.album_art_size = {f32(width), f32(height)}
		}
		else {
			state.album_art_ratio = 1
		}
		
		os2.file_info_delete(state.file_info, context.allocator)
		state.file_info = os2.stat(track_path, context.allocator) or_else {}
	}
	
	if state.displayed_track_id == 0 {
		imgui.TextDisabled("No track")
		return true
	}

	// Album art
	if imgui.CollapsingHeader("Album Art", {.DefaultOpen}) {
		imgui.PushStyleColor(.Button, 0)
		imgui.PushStyleColor(.ButtonActive, 0)
		imgui.PushStyleColor(.ButtonHovered, 0)
		imgui.PushStyleVarImVec2(.FramePadding, {})
		width := min(imgui.GetContentRegionAvail().x, 512)
		if state.album_art != 0 {
			if state.crop_album_art {
				ratio := state.album_art_ratio
				uv0: [2]f32
				uv1: [2]f32

				if state.album_art_ratio > 1 {
					// width < height
					r := 1/ratio
					uv0.x = 0
					uv0.y = 0.5 - (r*0.5)
					uv1.x = 1
					uv1.y = uv0.y + r
				}
				else if state.album_art_ratio < 1 {
					// width > height
					uv0.x = 0.5 - (ratio*0.5)
					uv0.y = 0
					uv1.x = uv0.x + ratio
					uv1.y = 1
				}
				else {
					uv0 = {0, 0}
					uv1 = {1, 1}
				}

				imgui.ImageButton(
					"##album_art", to_texture_ref(state.album_art),
					{width, width}, uv0, uv1
				)
			}
			else {
				imgui.ImageButton(
					"##album_art", to_texture_ref(state.album_art),
					{width, width * state.album_art_ratio}
				)
			}
		}
		else {
			imgui.InvisibleButton("##album_art", {width, width})
		}
		imgui.PopStyleVar()
		imgui.PopStyleColor(3)
	}

	track := server.library_find_track(sv.library, state.track_id) or_return
	metadata := track.properties

	if imgui.BeginItemTooltip() {
		imx.textf(32, "%dx%d", int(state.album_art_size.x), int(state.album_art_size.y))
		imgui.Separator()
		imx.text_unformatted("Right-click for options")
		imgui.EndTooltip()
	}

	if imgui.BeginPopupContextItem() {
		if imgui.BeginMenu("Add to playlist") {
			for &playlist in sv.library.playlists {
				if playlist.auto_build_params != nil do continue
				if imgui.MenuItem(playlist.name_cstring) {
					server.playlist_add_tracks(&playlist, &sv.library, {track.id})
				}
			}
			imgui.EndMenu()
		}

		imgui.Separator()
		if imgui.MenuItem("Play similar music") {
			track_index, found := server.library_find_track_index(sv.library, track.id)
			if found {
				radio := server.library_build_track_radio(sv.library, track_index, context.allocator)
				defer delete(radio)
				server.play_playlist(sv, radio, {.Generated, 0}, track.id)
			}
		} 
		if imgui.MenuItem("More by this artist") do go_to_artist(cl, metadata)
		if imgui.MenuItem("View album") do go_to_album(cl, metadata)
		if imgui.MenuItem("View genre") do go_to_genre(cl, metadata)
		imgui.Separator()

		imgui.MenuItemBoolPtr("Crop image", nil, &state.crop_album_art)
		imgui.EndPopup()
	}

	string_row :: proc(name: cstring, value: string, uptime: f64) -> (clicked: bool) {
		if value == "" {return}
		imgui.TableNextRow()

		if imgui.TableSetColumnIndex(0) {
			clicked = imgui.Selectable(name, false, {.SpanAllColumns})
			imx.set_item_tooltip_unformatted(value)

			if imgui.BeginPopupContextItem() {
				if imgui.MenuItem("Copy to clipboard") {
					value_cstring := strings.clone_to_cstring(value)
					imgui.SetClipboardText(value_cstring)
					delete(value_cstring)
				}
				imgui.EndPopup()
			}
		}

		if imgui.TableSetColumnIndex(1) {
			imx.scrolling_text(value, imgui.GetContentRegionAvail().x)
		}

		return clicked
	}

	number_row :: proc(name: cstring, value: i64) {
		if value == 0 {return}
		imgui.TableNextRow()

		if imgui.TableSetColumnIndex(0) {
			imgui.TextUnformatted(name)
		}

		if imgui.TableSetColumnIndex(1) {
			imx.text(16, value)
		}
	}

	metadata_string_row :: proc(name: cstring, md: Track_Properties, component: Track_Property_ID, uptime: f64) -> (clicked: bool) {
		v := md[component].(string) or_return
		if v == "" {return}
		return string_row(name, v, uptime)
	}

	metadata_date_row :: proc(name: string, md: Track_Properties, component: Track_Property_ID) -> bool {
		value := md[component].(i64) or_return
		imgui.TableNextRow()

		if imgui.TableSetColumnIndex(0) {
			imx.text_unformatted(name)
		}

		if imgui.TableSetColumnIndex(1) {
			buf: [16]u8
			ts := time.unix(value, 0)
			str := time.to_string_yyyy_mm_dd(ts, buf[:])
			imx.text_unformatted(str)
		}

		return false
	}

	// Tags
	imgui.SeparatorText("Metadata")
	if imgui.BeginTable("##metadata", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_BordersInnerH|imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("name", {}, 0.2)
		imgui.TableSetupColumn("value", {}, 0.8)

		metadata_string_row("Title", metadata, .Title, cl.uptime)
		if metadata_string_row("Artist", metadata, .Artist, cl.uptime) {go_to_artist(cl, metadata)}
		if metadata_string_row("Album", metadata, .Album, cl.uptime) {go_to_album(cl, metadata)}
		if metadata_string_row("Genre", metadata, .Genre, cl.uptime) {go_to_genre(cl, metadata)}

		number_row("Track no.", metadata[.TrackNumber].(i64) or_else 0)
		number_row("Year", metadata[.Year].(i64) or_else 0)

		imgui.TableNextRow()
		if imgui.TableSetColumnIndex(0) {imx.text_unformatted("Duration")}
		if imgui.TableSetColumnIndex(1) {
			h, m, s := time.clock_from_seconds(auto_cast (metadata[.Duration].(i64) or_else 0))
			imgui.Text("%02d:%02d:%02d", i32(h), i32(m), i32(s))
		}

		metadata_date_row("Date added", metadata, .DateAdded)
		
		imgui.EndTable()
	}
	
	imgui.SeparatorText("File properties")
	if imgui.BeginTable("##file_properies", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_BordersInnerH|imgui.TableFlags_RowBg) {
		path_buf: [512]u8
		
		imgui.TableSetupColumn("name", {}, 0.2)
		imgui.TableSetupColumn("value", {}, 0.8)
		
		path := server.library_find_track_path(sv.library, path_buf[:], state.track_id) or_else ""
		string_row("File path", path, cl.uptime)
		
		imgui.TableNextRow()
		if imgui.TableSetColumnIndex(0) {
			imx.text_unformatted("Size")
		}
		if imgui.TableSetColumnIndex(1) {
			imx.textf(16, "%M", state.file_info.size)
		}

		metadata_date_row("Date created", metadata, .FileDate)

		imgui.EndTable()
	}

	return
}

metadata_window_hide_proc :: proc(self: ^Window_Base) {
	state := cast(^Metadata_Window) self
	os2.file_info_delete(state.file_info, context.allocator)
	sys.video_destroy_texture(state.album_art)
	state.album_art = 0
	state.file_info = {}
	state.displayed_track_id = 0
}

Metadata_Editor_Window :: struct {
	using base: Window_Base,
	artist: [128]u8,
	title: [128]u8,
	album: [128]u8,
	genre: [128]u8,
	year: i32,

	enable_artist, enable_album, enable_title, enable_genre: bool,

	serial: uint,
	library_serial: uint,
	tracks: [dynamic]Track_ID,
	track_table: Track_Table,

	write_to_file: bool,
}

METADATA_EDITOR_WINDOW_ARCHETYPE := Window_Archetype {
	title = "Metadata Editor",
	internal_name = WINDOW_METADATA_EDITOR,
	make_instance = metadata_editor_window_make_instance_proc,
	show = metadata_editor_window_show_proc,
	hide = metadata_editor_window_hide_proc,
	flags = {.NoInitialInstance},
}

metadata_editor_window_make_instance_proc :: proc(allocator := context.allocator) -> ^Window_Base {
	return new(Metadata_Editor_Window, allocator)
}

metadata_editor_window_hide_proc :: proc(self: ^Window_Base) {
	state := cast(^Metadata_Editor_Window) self
	track_table_free(&state.track_table)
}

metadata_editor_window_show_proc :: proc(self: ^Window_Base, cl: ^Client, sv: ^Server) {
	state := cast(^Metadata_Editor_Window) self

	if len(state.tracks) == 0 {
		imgui.TextDisabled("No tracks selected for editing")
		return
	}

	imgui.TextDisabled("Editing %d tracks", i32(len(state.tracks)))

	string_row :: proc(name: cstring, buf: []u8, enable: ^bool) {
		imgui.PushIDPtr(enable)
		defer imgui.PopID()
		imgui.BeginDisabled(!enable^)
		imgui.InputText(name, cstring(raw_data(buf)), len(buf))
		imgui.EndDisabled()
		imgui.SameLine()
		imgui.Checkbox("##checkbox", enable)
	}

	string_row("Title", state.title[:], &state.enable_title)
	string_row("Artist", state.artist[:], &state.enable_artist)
	string_row("Album", state.album[:], &state.enable_album)
	string_row("Genre", state.genre[:], &state.enable_genre)

	imgui.Checkbox("Write to file", &state.write_to_file)
	imgui.SetItemTooltip("Save metadata changes to drive. Cannot be undone.")

	if imgui.Button("Apply") {
		alter: server.Library_Track_Metadata_Alteration
		alter.tracks = state.tracks[:]
		alter.values[.Title] = state.enable_title ? string(cstring(&state.title[0])) : nil
		alter.values[.Artist] = state.enable_artist ? string(cstring(&state.artist[0])) : nil
		alter.values[.Album] = state.enable_album ? string(cstring(&state.album[0])) : nil
		alter.values[.Genre] = state.enable_genre ? string(cstring(&state.genre[0])) : nil
		alter.write_to_file = state.write_to_file
		server.library_alter_metadata(&sv.library, alter)
	}

	if imgui.CollapsingHeader("View tracks") {
		if state.library_serial != sv.library.serial {
			state.library_serial = sv.library.serial
			state.serial += 1
		}

		context_id := imgui.GetID("##track_context")

		on_remove :: proc(data: rawptr, tracks: []Track_ID) {
			state := cast(^Metadata_Editor_Window) data
			for id in tracks {
				index := slice.linear_search(state.tracks[:], id) or_continue
				ordered_remove(&state.tracks, index)
			}

			state.serial += 1
		}

		show_track_table(&state.track_table, cl, sv, Track_Table_Info {
			callback_data = state,
			remove_callback = on_remove,
			str_id = "##editing_tracks",
			tracks_serial = state.serial,
			playlist_id = {.Generated, 1},
			tracks = state.tracks[:],
			flags = {.NoPlay, .NoFilter},
		})
	}

}

metadata_editor_window_select_tracks :: proc(state: ^Metadata_Editor_Window, tracks: []Track_ID) {
	resize(&state.tracks, len(tracks))
	copy(state.tracks[:], tracks)
	state.serial += 1
}
