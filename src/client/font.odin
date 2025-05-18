package client

import "core:slice"
import "core:mem"

import imgui "src:thirdparty/odin-imgui"

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

// If path is nil, data is used
Load_Font :: struct {
	data: []u8,
	path: cstring,
	size: f32,
	languages: Font_Languages,
}

@(private="file")
ICON_RANGES := []imgui.Wchar {
	0xf048, 0xf052, // Playback controls
	0xf026, 0xf028, // Volume
	0xf074, 0xf074, // Shuffle
	0xf079, 0xf079, // Repeat
	0xf001, 0xf001, // Music
	0
}

get_font_language_ranges :: proc(lang: Font_Languages, allocator := context.temp_allocator) -> []imgui.Wchar {
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
	if mem.scratch_allocator_init(&scratch, 16<<20) != nil {return}
	defer mem.scratch_allocator_destroy(&scratch)

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

	if len(fonts) == 0 {
		imgui.FontAtlas_AddFontDefault(atlas)
		cfg.MergeMode = true
	}

	imgui.FontAtlas_Build(atlas)

	// @TODO: Save font info
	//delete(client.loaded_fonts)
	//client.loaded_fonts = slice.clone(fonts)
}

