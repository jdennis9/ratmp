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
package client

import "core:mem"
import "core:log"
import "core:strings"

import "src:sys"

import imgui "src:thirdparty/odin-imgui"

// If path is nil, data is used
Load_Font :: struct {
	data: []u8,
	path: cstring,
	size: f32,
	languages: sys.Font_Languages,
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
	0
}

get_font_language_ranges :: proc(lang: sys.Font_Languages, allocator := context.temp_allocator) -> []imgui.Wchar {
	builder: imgui.FontGlyphRangesBuilder
	vector: imgui.Vector_Wchar
	defer imgui.Vector_Destruct(&vector)

	atlas := imgui.GetIO().Fonts

	imgui.FontGlyphRangesBuilder_Clear(&builder)

	if .ChineseFull in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesChineseFull(atlas)
		)
	}

	if .ChineseSimplifiedCommon in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesChineseSimplifiedCommon(atlas)
		)
	}

	if .Cyrillic in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesCyrillic(atlas)
		)
	}

	if .English in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesDefault(atlas)
		)
	}

	if .Greek in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesGreek(atlas)
		)
	}

	if .Japanese in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesJapanese(atlas)
		)
	}

	if .Korean in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesKorean(atlas)
		)
	}

	if .Thai in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesThai(atlas)
		)
	}

	if .Vietnamese in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			imgui.FontAtlas_GetGlyphRangesVietnamese(atlas)
		)
	}

	if .Icons in lang {
		imgui.FontGlyphRangesBuilder_AddRanges(
			&builder,
			raw_data(ICON_RANGES)
		)
	}

	imgui.FontGlyphRangesBuilder_BuildRanges(&builder, &vector)

	output := make([]imgui.Wchar, vector.Size, allocator)
	copy(output, (cast([^]imgui.Wchar)vector.Data)[:vector.Size])

	return output
}

load_fonts :: proc(client: ^Client, fonts: []Load_Font) {
	scratch: mem.Scratch
	have_english_font: bool

	if mem.scratch_allocator_init(&scratch, 256<<10) != nil {return}
	defer mem.scratch_allocator_destroy(&scratch)

	sys.imgui_invalidate_objects()
	defer sys.imgui_create_objects()

	io := imgui.GetIO()
	atlas := io.Fonts
	cfg := imgui.FontConfig {
		FontDataOwnedByAtlas = false,
		OversampleH = 2,
		OversampleV = 2,
		GlyphMaxAdvanceX = max(f32),
		RasterizerMultiply = 1,
		RasterizerDensity = 1,
		EllipsisChar = max(imgui.Wchar),
		MergeMode = false,
	}

	imgui.FontAtlas_Clear(atlas)

	for font in fonts {have_english_font |= .English in font.languages}

	if !have_english_font || len(fonts) == 0 {
		log.debug("Loading default font")
		imgui.FontAtlas_AddFontDefault(atlas)
		cfg.MergeMode = true
	}

	for font in fonts {
		glyph_ranges := get_font_language_ranges(font.languages, mem.scratch_allocator(&scratch))

		if font.path != nil {
			cfg.FontDataOwnedByAtlas = true
			imgui.FontAtlas_AddFontFromFileTTF(atlas, font.path, font.size, &cfg, raw_data(glyph_ranges))
		}
		else {
			cfg.FontDataOwnedByAtlas = false
			imgui.FontAtlas_AddFontFromMemoryTTF(
				atlas, raw_data(font.data), auto_cast len(font.data),
				font.size, &cfg, raw_data(glyph_ranges)
			)
		}

		cfg.MergeMode = true
	}


	imgui.FontAtlas_Build(atlas)
}

load_fonts_from_settings :: proc(cl: ^Client, scale: f32) {
	path_scratch_allocator: mem.Scratch_Allocator
	path_allocator: mem.Allocator

	mem.scratch_init(&path_scratch_allocator, 16<<10)
	defer mem.scratch_destroy(&path_scratch_allocator)

	path_allocator = mem.scratch_allocator(&path_scratch_allocator)
	
	system_fonts := sys.get_font_list()
	fonts: [dynamic]Load_Font
	have_lang: [sys.Font_Language]bool
	defer delete(fonts)

	for &font, index in cl.settings.fonts {
		handle: sys.Font_Handle
		path_buf: [512]u8

		if font.size == 0 {continue}
		handle = sys.font_handle_from_name(system_fonts, string(cstring(&font.name[0]))) or_continue
		path := sys.get_font_path(path_buf[:], handle) or_continue
		
		append(&fonts, Load_Font {
			languages = {index},
			size = f32(font.size) * scale,
			path = strings.clone_to_cstring(path, path_allocator),
		})

		have_lang[index] = true
	}

	if !have_lang[.English] {
		append(&fonts, Load_Font {
			languages = {.English},
			size = 16 * scale,
			data = #load("data/NotoSans-SemiBold.ttf"),
		})
	}

	if !have_lang[.Icons] {
		append(&fonts, Load_Font {
			languages = {.Icons},
			size = 11 * scale,
			data = #load("data/FontAwesome.otf"),
		})
	}

	load_fonts(cl, fonts[:])
}
