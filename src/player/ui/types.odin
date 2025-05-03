#+private
package ui

import "player:library"
import "player:playback"

_Layout_Name :: [64]u8
Track_ID :: library.Track_ID
Playlist_ID :: library.Playlist_ID
Library :: library.Library
Playback :: playback.State

Window :: enum {
	Library,
	Navigation,
	Artists,
	Albums,
	Folders,
	Genres,
	Queue,
	PlaylistTabs,
	Playlist,
	Metadata,
	ThemeEditor,
	ReplaceMetadata,
	EditMetadata,
	PeakMeter,
	Spectrum,
	WavePreview,
}

Window_Category :: enum {
	Music,
	Info,
	Editing,
	Visualizers,
}

Window_Info :: struct {
	name: cstring,
	internal_name: cstring,
	category: Window_Category,
}

_WINDOW_INFO := [Window]Window_Info {
	.Library = {
		name = "Library", internal_name = "library",
		category = .Music,
	},
	.Navigation = {
		name = "Navigation", internal_name = "navigation",
		category = .Music,
	},
	.Artists = {
		name = "Artists", internal_name = "artists",
		category = .Music,
	},
	.Albums = {
		name = "Albums", internal_name = "albums",
		category = .Music,
	},
	.Folders = {
		name = "Folders", internal_name = "folders",
		category = .Music,
	},
	.Genres = {
		name = "Genres", internal_name = "genres",
		category = .Music,
	},
	.Queue = {
		name = "Queue", internal_name = "queue",
		category = .Info,
	},
	.Playlist = {
		name = "Playlist", internal_name = "playlist",
		category = .Music,
	},
	.PlaylistTabs = {
		name = "Playlists (Tabs)", internal_name = "playlist_tabs",
		category = .Music,
	},
	.Metadata = {
		name = "Metadata", internal_name = "metadata",
		category = .Info,
	},
	.ThemeEditor = {
		name = "Edit Theme", internal_name = "theme_editor",
		category = .Editing,
	},
	.ReplaceMetadata = {
		name = "Replace Metadata", internal_name = "replace_metadata",
		category = .Editing,
	},
	.EditMetadata = {
		name = "Edit Metadata", internal_name = "edit_metadata",
		category = .Editing,
	},
	.PeakMeter = {
		name = "Peak Meter", internal_name = "peak_meter",
		category = .Visualizers,
	},
	.Spectrum = {
		name = "Spectrum", internal_name = "spectrum",
		category = .Visualizers,
	},
	.WavePreview = {
		name = "Wave Preview", internal_name = "wave_preview",
		category = .Visualizers,
	},
}

_WINDOW_CATEGORY_INFO := [Window_Category]struct {
	name: cstring,	
} {
	.Editing = {"Editing"},
	.Info = {"Info"},
	.Music = {"Music"},
	.Visualizers = {"Visualizers"},
}
