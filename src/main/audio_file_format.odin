package main

import "core:strings"

Audio_File_Format :: enum u8 {
	Wav,
	Flac,
	Ogg,
	Opus,
	M4a,
	Mp3,
	Ape,
	Aiff,
	Aac,
	Alac,
	Wma,
}

AUDIO_FILE_FORMAT_EXTENSIONS := [Audio_File_Format][]string {
	.Wav = {".wav", ".rf64"},
	.Flac = {".flac"},
	.Ogg = {".ogg", ".oga"},
	.Opus = {".opus"},
	.M4a = {".m4a"},
	.Mp3 = {".mp3"},
	.Ape = {".ape"},
	.Aiff = {".aiff"},
	.Aac = {".aac"},
	.Alac = {".alac"},
	.Wma = {".wma"},
}

Audio_File_Format_Display_Name :: struct {
	short, long: string,
}

AUDIO_FILE_FORMAT_DISPLAY_NAMES := [Audio_File_Format]Audio_File_Format_Display_Name {
	// Short name, long name
	.Wav  = {"WAV",  "Microsoft WAV"},
	.Flac = {"FLAC", "Free Lossless Audio Codec (FLAC)"},
	.Ogg  = {"OGG",  "Ogg Vorbis"},
	.Opus = {"OPUS", "Opus"},
	.M4a  = {"M4A",  "MPEG-4 Audio"},
	.Mp3  = {"MP3",  "MPEG-3"},
	.Ape  = {"APE",  "Monkey's Audio APE"},
	.Aiff = {"AIFF", "Apple AIFF"},
	.Aac  = {"AAC",  "Advanced Audio Coding (AAC)"},
	.Alac = {"ALAC", "Apple Lossless Audio Codec (ALAC)"},
	.Wma  = {"WMA",  "Windows Media Audio (WMA)"},
}

audio_file_format_from_extension :: proc(ext: string) -> (Audio_File_Format, bool) {
	as_lower := strings.to_lower(ext)
	defer delete(as_lower)

	for format_ext, format in AUDIO_FILE_FORMAT_EXTENSIONS {
		for e in format_ext {
			if ext == e {
				return format, true
			}
		}
	}

	return .Wav, false
}
