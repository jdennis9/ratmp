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

import "core:reflect"
import "core:math/linalg"
import sa "core:container/small_array"
import "base:runtime"
import "core:fmt"
import imgui "src:thirdparty/odin-imgui"

import "src:server"

Server :: server.Server
Library :: server.Library
Playlist :: server.Playlist
Playlist_ID :: server.Playlist_ID
Track_ID :: server.Track_ID
Track_Properties :: server.Track_Properties
Metadata_Component :: server.Track_Property_ID

Window_Flag :: enum {
	AlwaysShow,
	DontSaveState,
	DefaultShow,
	DontShowInSelector,
	// Memory of instance itself needs to be freed. Set by default with add_window_instance
	LooseMemory,
}
Window_Flags :: bit_set[Window_Flag]

Window_ID :: struct {hash: u32, instance: u32}

Window_Property_Variant :: union {
	int,
	string,
	bool,
}

/*Window_Info :: struct {
	display_name: cstring,
	internal_name: cstring,
	imgui_flags: imgui.WindowFlags,
	flags: Window_Flags,
}*/

Saved_Window :: struct {
	internal_name: cstring,
	imgui_flags: imgui.WindowFlags,
	open: bool,
}

Base_Window_ID :: enum {
	Library,
	Queue,
	Playlists,
	Artists,
	Albums,
	Genres,
	Folders,
	Metadata,
	ThemeEditor,
	Spectrum,
	WaveformSeek,
	Oscilloscope,
	Settings,
	MetadataEditor,
}

WINDOW_LIBRARY :: "ratmp_library"
WINDOW_QUEUE :: "ratmp_queue"
WINDOW_PLAYLISTS :: "ratmp_playlists"
WINDOW_ARTIST :: "ratmp_artists"
WINDOW_ALBUMS :: "ratmp_albums"
WINDOW_GENRES :: "ratmp_genres"
WINDOW_FOLDERS :: "ratmp_folders"
WINDOW_METADATA :: "ratmp_metadata"
WINDOW_THEME_EDITOR :: "ratmp_theme_editor"
WINDOW_WAVEBAR :: "ratmp_wavebar"
WINDOW_SPECTRUM :: "ratmp_spectrum"
WINDOW_OSCILLOSCOPE :: "ratmp_oscilloscope"
WINDOW_SETTINGS :: "ratmp_settings"
WINDOW_METADATA_EDITOR :: "ratmp_metadata_editor"
WINDOW_WINDOW_MANAGER :: "ratmp_window_manager"
WINDOW_VECTORSCOPE :: "ratmp_vectorscope"
WINDOW_SPECTOGRAM :: "ratmp_spectogram"

Window_State :: struct {
	show: bool,
	bring_to_front: bool,
	flags: imgui.WindowFlags,
}

is_key_chord_pressed :: proc(mods: imgui.Key, key: imgui.Key) -> bool {
	return imgui.IsKeyChordPressed(auto_cast(mods | key))
}

is_play_track_input_pressed :: proc() -> bool {
	return imgui.IsItemClicked(.Middle) || (imgui.IsItemClicked(.Left) && imgui.IsMouseDoubleClicked(.Left))
}

safe_lerp :: proc(a, b, t: $T) -> T {
	return linalg.lerp(a, b, linalg.clamp(t, 0, 1))
}

enum_cstring :: proc(buf: []u8, value: $T) -> cstring {
	copy(buf[:len(buf)-1], reflect.enum_name_from_value(value) or_else "")
	return cstring(raw_data(buf))
}
