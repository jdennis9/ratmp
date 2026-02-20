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
package licenses

License_ID :: enum {
	FFmpeg,
	FreeType,
	ImGui,
	TagLib,
	Opus,
}

License :: struct {
	name: string,
	ownage: string,
	url: string,
}

@private
OPUS_OWNAGE :: `
2001-2023 Xiph.Org, Skype Limited, Octasic,
Jean-Marc Valin, Timothy B. Terriberry,
CSIRO, Gregory Maxwell, Mark Borgerding,
Erik de Castro Lopo, Mozilla, Amazon
`

@private
licenses := [License_ID]License {
	.FFmpeg = {
		name = "FFmpeg",
		ownage = "2001 Fabrice Bellard",
		url = "https://ffmpeg.org/",
	},
	.FreeType = {
		name = "FreeType",
		ownage = "1996-2002, 2006 by\nDavid Turner, Robert Wilhelm, and Werner Lemberg",
		url = "https://freetype.org/",
	},
	.ImGui = {
		name = "ImGui",
		ownage = "2014-2025 Omar Cornut",
		url = "https://github.com/ocornut/imgui",
	},
	.TagLib = {
		name = "TagLib",
		ownage = "2002-2008 by Scott Wheeler",
		url = "https://taglib.org/",
	},
	.Opus = {
		name = "Opus",
		ownage = OPUS_OWNAGE,
		url = "https://opus-codec.org/",
	},
}

get_license :: proc() -> License {
	return {
		name = "RAT MP",
		ownage = "2025-2026 Jamie Dennis",
		url = "https://github.com/jdennis9/ratmp",
	}
}

get_third_party_licenses :: proc() -> [License_ID]License {
	return licenses
}
