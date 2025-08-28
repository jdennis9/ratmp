#+private
package client

import "core:strings"
import "core:time"
import "core:os/os2"
import "core:slice"
import "core:log"

import stbi "vendor:stb/image"

import imgui "src:thirdparty/odin-imgui"
import "src:bindings/taglib"

import "src:util"
import "src:server"
import "src:sys"
import "src:decoder"

import "imx"

_Metadata_Window :: struct {
	current_track_id: Track_ID,
	album_art: imgui.TextureID,
	album_art_ratio: f32,
	file_info: os2.File_Info,
}

_load_track_album_art :: proc(client: Client, str_path: string) -> (w, h: int, texture: imgui.TextureID, ok: bool) {
	data: rawptr
	data, w, h = decoder.load_thumbnail(str_path) or_return
	defer decoder.delete_thumbnail(data)
	texture = sys.imgui_create_texture(data, w, h) or_return

	ok = true
	return
}

_show_metadata_details :: proc(client: ^Client, sv: ^Server, track_id: Track_ID, state: ^_Metadata_Window) -> (ok: bool) {
	if state.current_track_id != track_id {
		width, height: int
		have_art: bool

		state.current_track_id = track_id

		sys.imgui_destroy_texture(state.album_art)
		state.album_art = 0

		if track_id == 0 {
			return
		}

		path_buf: Path
		track_path := server.library_get_track_path(sv.library, path_buf[:], track_id) or_return
		width, height, state.album_art, have_art = _load_track_album_art(client^, track_path)
		if have_art {
			state.album_art_ratio = f32(height) / f32(width)
		}
		else {
			state.album_art_ratio = 1
		}

		os2.file_info_delete(state.file_info, context.allocator)
		state.file_info = os2.stat(track_path, context.allocator) or_else {}
	}
	
	if state.current_track_id == 0 {
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
			if client.settings.crop_album_art {
				ratio := state.album_art_ratio
				uv0: [2]f32
				uv1: [2]f32

				if state.album_art_ratio > 1 {
					// width < height
					uv0.x = 0
					uv0.y = 0.5 - (ratio*0.5)
					uv1.x = 1
					uv1.y = uv0.y + ratio
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

				imgui.ImageButton("##album_art", state.album_art, {width, width}, uv0, uv1)
			}
			else {
				imgui.ImageButton("##album_art", state.album_art, {width, width * state.album_art_ratio})
			}
		}
		else {
			imgui.InvisibleButton("##album_art", {width, width})
		}
		imgui.PopStyleVar()
		imgui.PopStyleColor(3)
	}

	metadata := server.library_get_track_metadata(sv.library, track_id) or_return

	if imgui.BeginPopupContextItem() {
		result: _Track_Context_Result
		result.single_track = track_id
		_track_show_context_items(track_id, &result, sv^)
		_track_process_context(track_id, result, client, sv, {}, true)
		imgui.MenuItemBoolPtr("Crop image", nil, &client.settings.crop_album_art)
		imgui.EndPopup()
	}


	string_row :: proc(name: cstring, value: string) {
		if value == "" {return}
		imgui.TableNextRow()

		if imgui.TableSetColumnIndex(0) {
			imgui.Selectable(name, false, {.SpanAllColumns})
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
			imx.text_unformatted(value)
		}
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

	// Tags
	imgui.SeparatorText("Metadata")
	if imgui.BeginTable("##metadata", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_BordersInnerH|imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("name", {}, 0.12)
		imgui.TableSetupColumn("value", {}, 0.88)

		for component in Metadata_Component {
			switch v in metadata.values[component] {
				case string: {
					//string_row(&metadata, component, v)
					string_row(server.METADATA_COMPONENT_NAMES[component], metadata.values[component].(string) or_else "")
				}
				case i64: {
					//number_row(server.METADATA_COMPONENT_NAMES[component], metadata.values[component].(i64) or_else 0)
				}
			}
		}

		imgui.TableNextRow()
		if imgui.TableSetColumnIndex(0) {imx.text_unformatted("Duration")}
		if imgui.TableSetColumnIndex(1) {
			h, m, s := time.clock_from_seconds(auto_cast (metadata.values[.Duration].(i64) or_else 0))
			imgui.Text("%02d:%02d:%02d", i32(h), i32(m), i32(s))
		}

		imgui.EndTable()
	}

	imgui.SeparatorText("File properties")
	if imgui.BeginTable("##file_properies", 2, imgui.TableFlags_SizingStretchProp|imgui.TableFlags_BordersInnerH|imgui.TableFlags_RowBg) {
		path_buf: [512]u8

		imgui.TableSetupColumn("name", {}, 0.12)
		imgui.TableSetupColumn("value", {}, 0.88)

		path := server.library_get_track_path(sv.library, path_buf[:], track_id) or_else ""
		string_row("File path", path)

		// File size
		imgui.TableNextRow()
		if imgui.TableSetColumnIndex(0) {
			imx.text_unformatted("Size")
		}
		if imgui.TableSetColumnIndex(1) {
			imx.textf(16, "%.2f MiB", f32(state.file_info.size) / (1024*1024))
		}

		imgui.EndTable()
	}

	return
}

_Metadata_Editor :: struct {
	artist: [128]u8,
	title: [128]u8,
	album: [128]u8,
	genre: [128]u8,
	year: i32,

	enable_artist, enable_album, enable_title, enable_genre: bool,

	serial: uint,
	library_serial: uint,
	tracks: [dynamic]Track_ID,
	track_table: _Track_Table_2,
}

_show_metadata_editor :: proc(cl: ^Client, sv: ^Server) {
	state := &cl.windows.metadata_editor

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

	if imgui.Button("Apply") {
		alter: server.Library_Track_Metadata_Alteration
		alter.tracks = state.tracks[:]
		alter.values[.Title] = state.enable_title ? string(cstring(&state.title[0])) : nil
		alter.values[.Artist] = state.enable_artist ? string(cstring(&state.artist[0])) : nil
		alter.values[.Album] = state.enable_album ? string(cstring(&state.album[0])) : nil
		alter.values[.Genre] = state.enable_genre ? string(cstring(&state.genre[0])) : nil
		server.library_alter_metadata(&sv.library, alter)
	}

	if imgui.CollapsingHeader("View tracks") {
		if state.library_serial != sv.library.serial {
			state.library_serial = sv.library.serial
			state.serial += 1
		}

		context_id := imgui.GetID("##track_context")

		_track_table_update(&state.track_table, state.serial, sv.library, state.tracks[:], {}, "")
		table_result := _track_table_show(state.track_table, "##tracks", context_id, sv.current_track_id)
		context_result := _track_table_show_context(state.track_table, table_result, context_id, {.NoEditMetadata}, sv^)
		_track_table_process_context(state.track_table, table_result, context_result, cl, sv)

		if context_result.remove {
			sel := _track_table_get_selection(state.track_table)
			defer delete(sel)

			log.debug(sel)
			log.debug(state.tracks[:])

			for id in sel {
				index := slice.linear_search(state.tracks[:], id) or_continue
				ordered_remove(&state.tracks, index)
			}

			state.serial += 1
		}
	}

}

_metadata_editor_select_tracks :: proc(cl: ^Client, tracks: []Track_ID) {
	state := &cl.windows.metadata_editor
	resize(&state.tracks, len(tracks))
	copy(state.tracks[:], tracks)
	state.serial += 1

	_bring_window_to_front(cl, .MetadataEditor)
}
