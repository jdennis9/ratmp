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

import imgui "src:thirdparty/odin-imgui"

import "src:server"

Server :: server.Server
Playlist :: server.Playlist
Playlist_ID :: server.Playlist_ID
Track_ID :: server.Track_ID
Track_Metadata :: server.Track_Metadata
Metadata_Component :: server.Metadata_Component

_Window_Flag :: enum {
	AlwaysShow,
	DontSaveState,
}
_Window_Flags :: bit_set[_Window_Flag]

_Window :: enum {
	Library,
	Queue,
	Playlists,
	Artists,
	Albums,
	Genres,
	Folders,
	Metadata,
	WaveformSeek,
	Spectrum,
	Oscilloscope,
	ThemeEditor,
	Settings,
	MetadataEditor,
}

_Window_Info :: struct {
	display_name: cstring,
	internal_name: cstring,
	imgui_flags: imgui.WindowFlags,
	flags: _Window_Flags,
}

_WINDOW_INFO := [_Window]_Window_Info {
	.Library = {"Library", "library", {}, {.AlwaysShow}},
	.Queue = {"Queue", "queue", {}, {.AlwaysShow}},
	.Playlists = {"Playlists", "playlists", {}, {.AlwaysShow}},
	.Artists = {"Artists", "artists", {}, {}},
	.Albums = {"Albums", "albums", {}, {}},
	.Genres = {"Genres", "genres", {}, {}},
	.Folders = {"Folders", "folders", {}, {}},
	.Metadata = {"Metadata", "metadata", {.AlwaysVerticalScrollbar}, {.AlwaysShow}},
	.ThemeEditor = {"Edit Theme", "theme_editor", {}, {}},
	.Spectrum = {"Spectrum", "spectrum", {}, {}},
	.WaveformSeek = {"Wave Bar", "waveform", {}, {}},
	.Oscilloscope = {"Oscilloscope", "oscilloscope", {}, {}},
	.Settings = {"Settings", "settings", {}, {.DontSaveState}},
	.MetadataEditor = {"Metadata Editor", "metadata_editor", {}, {}}
}

_Window_State :: struct {
	show: bool,
	bring_to_front: bool,
	flags: imgui.WindowFlags,
}

//_Window_Proc :: #type proc(cl: ^Client, sv: ^Server, delta: f32, window: ^_Window_State)
