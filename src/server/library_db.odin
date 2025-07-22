package server

import "core:os/os2"
import "core:strings"
import "core:log"
import "core:hash/xxhash"
import "core:time"

import sqlite "src:thirdparty/odin-sqlite3"

import "src:path_pool"

library_save_to_file :: proc(lib: Library, path: string) {
	duration: time.Duration
	defer log.info("Saved library in", time.duration_milliseconds(duration), "ms")
	time.SCOPED_TICK_DURATION(&duration)

	db: ^sqlite.Connection
	error: sqlite.Result_Code
	path_cstring := strings.clone_to_cstring(path)
	exec_error: cstring
	defer delete(path_cstring)

	if remove_error := os2.remove(path); remove_error != nil {log.error(remove_error)}
	error = sqlite.open(path_cstring, &db)
	if error != .Ok {
		log.error("Error opening SQL database:", error)
		return
	}
	defer sqlite.close(db)

	// Create table
	error = sqlite.exec(db, `
	CREATE TABLE tracks (
		id BIGINT PRIMARY KEY,
		path VARCHAR(511),
		title VARCHAR(127),
		artist VARCHAR(127),
		album VARCHAR(127),
		genre VARCHAR(127),
		duration INTEGER,
		birate INTEGER,
		track_number INTEGER,
		year INTEGER,
		date_added BIGINT,
		file_date BIGINT
	)`, nil, nil, &exec_error)

	if error != .Ok {
		log.error(error, exec_error)
	}
	
	stmt: ^sqlite.Statement

	sqlite.exec(db, "BEGIN TRANSACTION", nil, nil, nil)

	for md, index in lib.track_metadata {
		path_buf: [512]u8
		path := path_pool.retrieve_cstring(lib.path_allocator, lib.track_paths[index], path_buf[:])
		path_hash := xxhash.XXH3_64_default(transmute([]u8) string(path))

		sqlite.prepare_v2(db, "INSERT INTO tracks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", -1, &stmt, nil)
		defer sqlite.finalize(stmt)

		es := string(cstring(""))

		sqlite.bind_int64(stmt, 1, auto_cast path_hash)
		sqlite.bind_text(stmt, 2, path, -1, nil)
		sqlite.bind_text(stmt, 3, strings.unsafe_string_to_cstring(md.values[.Title].(string) or_else es), -1, nil)
		sqlite.bind_text(stmt, 4, strings.unsafe_string_to_cstring(md.values[.Artist].(string) or_else es), -1, nil)
		sqlite.bind_text(stmt, 5, strings.unsafe_string_to_cstring(md.values[.Album].(string) or_else es), -1, nil)
		sqlite.bind_text(stmt, 6, strings.unsafe_string_to_cstring(md.values[.Genre].(string) or_else es), -1, nil)
		sqlite.bind_int(stmt, 7, auto_cast(md.values[.Duration].(i64) or_else 0))
		sqlite.bind_int(stmt, 8, auto_cast(md.values[.Bitrate].(i64) or_else 0))
		sqlite.bind_int(stmt, 9, auto_cast(md.values[.TrackNumber].(i64) or_else 0))
		sqlite.bind_int(stmt, 10, auto_cast(md.values[.Year].(i64) or_else 0))
		sqlite.bind_int64(stmt, 11, md.values[.DateAdded].(i64) or_else 0)
		sqlite.bind_int64(stmt, 12, md.values[.FileDate].(i64) or_else 0)
		sqlite.step(stmt)
	}

	sqlite.exec(db, "END TRANSACTION", nil, nil, nil)
}

library_load_from_file :: proc(lib: ^Library, path: string) -> (loaded: bool) {
	/*log.debug("Load library from", path)

	scratch: mem.Scratch
	if mem.scratch_allocator_init(&scratch, 16<<20) != nil {return false}
	defer {
		mem.scratch_allocator_destroy(&scratch)
	}

	allocator := mem.scratch_allocator(&scratch)

	file_data, file_error := os2.read_entire_file_from_path(path, context.allocator)
	if file_error != nil {
		log.error(file_error)
		return
	}
	defer delete(file_data)

	data: Json_Data
	marshal_error := json.unmarshal(file_data, &data, .JSON5, allocator)
	if marshal_error != nil {
		log.error(marshal_error)
		return
	}

	for track in data.tracks {
		metadata: Track_Metadata
		track_set_string(&metadata, .Title, track.title, lib.string_allocator)
		track_set_string(&metadata, .Artist, track.artist, lib.string_allocator)
		track_set_string(&metadata, .Genre, track.genre, lib.string_allocator)
		track_set_string(&metadata, .Album, track.album, lib.string_allocator)
		metadata.values[.Bitrate] = track.bitrate
		metadata.values[.Duration] = track.duration
		metadata.values[.TrackNumber] = track.track_number
		metadata.values[.Year] = track.year
		metadata.values[.DateAdded] = track.date_added

		library_add_track(lib, track.path, metadata)
	}

	loaded = true*/

	duration: time.Duration
	defer log.info("Loaded library in", time.duration_milliseconds(duration), "ms")
	time.SCOPED_TICK_DURATION(&duration)

	db: ^sqlite.Connection
	result: sqlite.Result_Code
	path_cstring := strings.clone_to_cstring(path)
	defer delete(path_cstring)
	
	result = sqlite.open(path_cstring, &db)
	if result != .Ok {
		log.error(result)
		return
	}
	defer sqlite.close(db)
	
	{
		stmt: ^sqlite.Statement
		sqlite.prepare_v2(db, "SELECT * FROM tracks", -1, &stmt, nil)
		defer sqlite.finalize(stmt)

		for {
			track: Track_Metadata
			result = sqlite.step(stmt)
			if result != .Row {break}

			//path_hash := u64(sqlite.column_int64(stmt, 1))
			path := sqlite.column_text(stmt, 1)
			track_set_cstring(&track, .Title, sqlite.column_text(stmt, 2), lib.string_allocator)
			track_set_cstring(&track, .Artist, sqlite.column_text(stmt, 3), lib.string_allocator)
			track_set_cstring(&track, .Album, sqlite.column_text(stmt, 4), lib.string_allocator)
			track_set_cstring(&track, .Genre, sqlite.column_text(stmt, 5), lib.string_allocator)
			track.values[.Duration] = i64(sqlite.column_int(stmt, 6))
			track.values[.Bitrate] = i64(sqlite.column_int(stmt, 7))
			track.values[.TrackNumber] = i64(sqlite.column_int(stmt, 8))
			track.values[.Year] = i64(sqlite.column_int(stmt, 9))
			track.values[.DateAdded] = i64(sqlite.column_int64(stmt, 10))
			track.values[.FileDate] = i64(sqlite.column_int64(stmt, 11))

			library_add_track(lib, string(path), track)
		}
	}

	return
}
