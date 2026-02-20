/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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
package client

import "core:mem"
import "core:strings"

import "src:sys"

import imgui "src:thirdparty/odin-imgui"

ICON_STOP :: ""
ICON_ARROW :: ""
ICON_SHUFFLE :: ""
ICON_PREVIOUS :: ""
ICON_NEXT :: ""
ICON_PLAY :: ""
ICON_PAUSE :: ""
ICON_REPEAT :: ""
ICON_REPEAT_SINGLE :: ""
ICON_EXPAND :: ""
ICON_COMPRESS :: ""

// If path is nil, data is used
Load_Font :: struct {
	data: []u8,
	path: cstring,
}

Font_Language :: enum {
	ChineseFull,
	ChineseSimplifiedCommon,
	Cyrillic,
	English,
	Greek,
	Japanese,
	Korean,
	Thai,
	Vietnamese,
	Icons,
}

Font_Languages :: bit_set[Font_Language]

@(private="file")
ICON_RANGES := []imgui.Wchar {
	0xf048, 0xf052, // Playback controls
	0xf026, 0xf028, // Volume
	0xf074, 0xf074, // Shuffle
	0xf021, 0xf021, // Repeat 1
	0xf0e2, 0xf0e2, // Repeat
	0xf001, 0xf001, // Music
	0xf061, 0xf061, // Arrow
	0xf065, 0xf066, // Expand and compress
	0
}

@(private="file")
_BUILTIN_FONT := #load("data/NotoSans-SemiBold.ttf")

load_fonts :: proc(client: ^Client, fonts: []Load_Font) {
	client.font_serial += 1

	io := imgui.GetIO()
	atlas := io.Fonts
	imgui.FontAtlas_ClearFonts(atlas)

	cfg := imgui.FontConfig {
		FontDataOwnedByAtlas = true,
		GlyphMaxAdvanceX = max(f32),
		RasterizerMultiply = 1,
		RasterizerDensity = 1,
	}

	for font in fonts {
		if font.path != nil {
			imgui.FontAtlas_AddFontFromFileTTF(atlas, font.path, 0, &cfg)
		}
		else {
			font_data := imgui.MemAlloc(auto_cast len(font.data))
			mem.copy(font_data, raw_data(font.data), len(font.data))
			imgui.FontAtlas_AddFontFromMemoryTTF(
				atlas, font_data, auto_cast len(font.data), 0, &cfg
			)
		}

		cfg.MergeMode = true
	}
}

load_fonts_from_settings :: proc(cl: ^Client, scale: f32) {
	path_scratch_allocator: mem.Scratch_Allocator
	path_allocator: mem.Allocator

	mem.scratch_init(&path_scratch_allocator, 16<<10)
	defer mem.scratch_destroy(&path_scratch_allocator)

	path_allocator = mem.scratch_allocator(&path_scratch_allocator)
	
	system_fonts := sys.get_font_list()
	fonts: [dynamic]Load_Font
	defer delete(fonts)

	if len(cl.settings.fonts) == 0 {
		append(&fonts, Load_Font {
			data = #load("data/NotoSans-SemiBold.ttf"),
		})
	}

	for &font in cl.settings.fonts {
		handle: sys.Font_Handle
		path_buf: [512]u8

		handle = sys.font_handle_from_name(system_fonts, string(cstring(&font.name[0]))) or_continue
		path := sys.get_font_path(path_buf[:], handle) or_continue
		
		append(&fonts, Load_Font {
			path = strings.clone_to_cstring(path, path_allocator),
		})
	}

	append(&fonts, Load_Font {
		data = #load("data/FontAwesome.otf"),
	})

	load_fonts(cl, fonts[:])
}
