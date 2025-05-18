#+private
package client

import "core:strings"
import "core:time"

import stbi "vendor:stb/image"

import imgui "src:thirdparty/odin-imgui"
import "src:bindings/taglib"

import "src:server"

_Metadata_Window :: struct {
	current_track_id: Track_ID,
	album_art: imgui.TextureID,
}

_load_track_album_art :: proc(client: Client, str_path: string) -> (texture: imgui.TextureID, ok: bool) {
	if client.create_texture_proc == nil {return}

	path_buf: Path
	path := cstring(&path_buf[0])

	server.copy_string_to_buf(path_buf[:], str_path)

	file := taglib.file_new(path)
	if file == nil {return}
	defer taglib.file_free(file)

	picture := taglib.complex_property_get(file, "PICTURE")
	if picture == nil {return}
	defer taglib.complex_property_free(picture)

	picture_data: taglib.Complex_Property_Picture_Data
	taglib.picture_from_complex_property(picture, &picture_data)

	if picture_data.data != nil {
		width, height: i32
		image_data := stbi.load_from_memory(
			picture_data.data, auto_cast picture_data.size,
			&width, &height, nil, 4
		)
		if image_data == nil {return}
		defer stbi.image_free(image_data)

		return client.create_texture_proc(image_data, auto_cast width, auto_cast height)
	}

	return
}

_show_metadata_details :: proc(client: ^Client, sv: ^Server, track_id: Track_ID, state: ^_Metadata_Window) -> (ok: bool) {
	if state.current_track_id != track_id {
		state.current_track_id = track_id

		client.destroy_texture_proc(state.album_art)
		state.album_art = nil

		if track_id == 0 {
			return
		}

		path_buf: Path
		track_path := server.library_get_track_path(sv.library, path_buf[:], track_id) or_return
		state.album_art = _load_track_album_art(client^, track_path) or_else nil
	}
	
	if state.current_track_id == 0 {
		imgui.TextDisabled("No track")
		return true
	}

	// Album art
	imgui.PushStyleColor(.Button, 0)
	imgui.PushStyleColor(.ButtonActive, 0)
	imgui.PushStyleColor(.ButtonHovered, 0)
	imgui.PushStyleVarImVec2(.FramePadding, {})
	size := imgui.GetContentRegionAvail().x
	imgui.ImageButton("##album_art", state.album_art, {size, size})
	imgui.PopStyleVar()
	imgui.PopStyleColor(3)

	metadata := server.library_get_track_metadata(sv.library, track_id) or_return

	if imgui.BeginPopupContextItem() {
		context_menu: _Track_Context_Menu_Result
		_show_generic_track_context_menu_items(client, sv, track_id, metadata, &context_menu)
		_process_track_context_menu_results(client, sv, context_menu, {track_id})
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
			_native_text_unformatted(value)
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
				}
			}
		}

		imgui.TableNextRow()
		if imgui.TableSetColumnIndex(0) {_native_text_unformatted("Duration")}
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

		imgui.EndTable()
	}

	return
}
