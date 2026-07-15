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
#+private file
package library

import "core:hash"
import "core:bytes"
import "core:io"
import "vendor:compress/lz4"
import "core:log"
import "src:main/shared"
import "core:os"
import "core:mem"
import "core:encoding/cbor"

_Header :: struct {
	magic:             u32,
	uncompressed_size: u32,
	crc:               u32, // crc of uncompressed data
}

_Track_Model :: struct {
	tags: Track_Tags,
	url:  string,
}

_Model :: struct {
	tracks: []_Track_Model,
}

MAGIC :: u32(0xbede4721)
MAX_UNCOMPRESSED_SIZE :: (256<<20)

@private
save_db_to_disk :: proc(path: string) -> shared.Error {
	scratch: mem.Scratch
	model: _Model

	shared.TIME_SCOPE("Save metadata to disk")

	file := os.create(path) or_return
	defer os.close(file)

	mem.scratch_init(&scratch, 512<<10)
	defer mem.scratch_destroy(&scratch)

	allocator := mem.scratch_allocator(&scratch)

	model.tracks = make([]_Track_Model, get_track_count())
	defer delete(model.tracks)

	iter := make_track_iterator()
	index := 0

	for track in iterate_tracks(&iter) {
		model.tracks[index].tags = convert_track_to_tags(track^, allocator)
		model.tracks[index].url  = track.url
		index += 1
	}

	raw, marshal_error := cbor.marshal_into_bytes(model)
	if marshal_error != nil {
		log.error(marshal_error)
		return false
	}

	compressed := make([]byte, lz4.compressBound(auto_cast len(raw)))
	defer delete(compressed)

	compressed_size := lz4.compress_HC(
		raw_data(raw), raw_data(compressed),
		auto_cast len(raw), auto_cast len(compressed), lz4.CLEVEL_DEFAULT
	)

	if compressed_size < 0 {
		log.error("Compression failed")
		return false
	}

	header := _Header {
		magic             = MAGIC,
		uncompressed_size = auto_cast len(raw),
		crc               = hash.crc32(raw[:]),
	}

	os.write(file, mem.any_to_bytes(header))
	os.write(file, compressed[:compressed_size])

	return nil
}

@private
load_db_from_disk :: proc(path: string) -> shared.Error {
	shared.TIME_SCOPE("Load metadata from disk")

	raw := os.read_entire_file_from_path(path, context.allocator) or_return
	defer delete(raw)
	
	scratch: mem.Scratch
	mem.scratch_init(&scratch, 512<<10)
	defer mem.scratch_destroy(&scratch)
	allocator := mem.scratch_allocator(&scratch)

	if len(raw) <= size_of(_Header) do return false

	compressed := raw[size_of(_Header):]
	header     := cast(^_Header) raw_data(raw)

	if header.magic != MAGIC {
		log.errorf("Magic mismatch (expected: %x, got: %x)", MAGIC, header.magic)
		return false
	}

	if header.uncompressed_size > MAX_UNCOMPRESSED_SIZE {
		log.error("Uncompressed data is too big, aborting")
		return false
	}

	if len(compressed) > auto_cast lz4.compressBound(auto_cast header.uncompressed_size) {
		log.error("Compressed data is larger than output size")
		return false
	}

	uncompressed := make([]byte, header.uncompressed_size)
	defer delete(uncompressed)

	bytes_decompressed := lz4.decompress_safe(
		raw_data(compressed), raw_data(uncompressed),
		auto_cast len(compressed), auto_cast len(uncompressed)
	)

	if bytes_decompressed < 0 {
		log.error("Decompression failed")
	}

	if bytes_decompressed != auto_cast header.uncompressed_size {
		log.error("Decompressed size does not match expected size")
		return false
	}

	model: _Model
	cbor.unmarshal_from_bytes(uncompressed, &model, {}, allocator)

	for t in model.tracks {
		add_track(t.tags, t.url)
	}

	return nil
}
