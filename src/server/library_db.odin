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
package server

import "base:runtime"
import "core:strconv"
import "core:os/os2"
import "core:strings"
import "core:log"
import "core:hash/xxhash"
import "core:time"

import sqlite "src:thirdparty/odin-sqlite3"

import "src:path_pool"

DB_VERSION :: 2
DB_VERSION_PRAGMA :: "PRAGMA user_version=2"

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

	// Track table
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

	// Cover art table
	error = sqlite.exec(db, `
	CREATE TABLE cover_art (
		dir_hash BIGINT PRIMARY KEY,
		path VARCHAR(511)
	)`, nil, nil, &exec_error)
	
	if error != .Ok {
		log.error(error, exec_error)
	}
	
	stmt: ^sqlite.Statement

	sqlite.exec(db, DB_VERSION_PRAGMA, nil, nil, nil)
	sqlite.exec(db, "BEGIN TRANSACTION", nil, nil, nil)

	// Tracks
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

	// Cover art
	sqlite.exec(db, "BEGIN TRANSACTION", nil, nil, nil)

	for dir_hash, cover_path in lib.dir_cover_files {
		if dir_hash == 0 || len(cover_path) == 0 {continue}
		error = sqlite.prepare_v2(db, "INSERT INTO cover_art VALUES (?, ?)", -1, &stmt, nil)
		defer sqlite.finalize(stmt)
		if error != .Ok {log.error(error)}

		sqlite.bind_int64(stmt, 1, auto_cast dir_hash)
		sqlite.bind_text(stmt, 2, cstring(raw_data(cover_path)), auto_cast len(cover_path), nil)
		sqlite.step(stmt)
	}

	sqlite.exec(db, "END TRANSACTION", nil, nil, nil)
}

library_load_from_file :: proc(lib: ^Library, path: string) -> (loaded_version: int, loaded: bool) {
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

	version: i32

	set_version :: proc "c" (ctx: rawptr, argc: i32, argv: [^]cstring, col_names: [^]cstring) -> i32 {
		if argc != 1 {return 0}
		context = runtime.default_context()
		version := cast(^i32) ctx
		version^ = cast(i32) (strconv.parse_i64(string(argv[0])) or_else 0)
		return 0
	}

	sqlite.exec(db, "PRAGMA user_version", set_version, &version, nil)
	loaded_version = auto_cast version

	log.info("DB version:", version)
	if version < 1 {log.info("DB does not contain file dates. They will be retrieved while the DB is loaded")}
	if version < 2 {log.info("DB does not contain cover art. Track folders will be scanned for image files")}

	// Tracks
	{
		stmt: ^sqlite.Statement
		sqlite.prepare_v2(db, "SELECT * FROM tracks", -1, &stmt, nil)
		defer sqlite.finalize(stmt)

		for {
			track: Track_Metadata
			result = sqlite.step(stmt)
			if result != .Row {break}

			path := sqlite.column_text(stmt, 1)
			if path == nil {continue}
			track_set_cstring(&track, .Title, sqlite.column_text(stmt, 2), lib.string_allocator)
			track_set_cstring(&track, .Artist, sqlite.column_text(stmt, 3), lib.string_allocator)
			track_set_cstring(&track, .Album, sqlite.column_text(stmt, 4), lib.string_allocator)
			track_set_cstring(&track, .Genre, sqlite.column_text(stmt, 5), lib.string_allocator)
			track.values[.Duration] = i64(sqlite.column_int(stmt, 6))
			track.values[.Bitrate] = i64(sqlite.column_int(stmt, 7))
			track.values[.TrackNumber] = i64(sqlite.column_int(stmt, 8))
			track.values[.Year] = i64(sqlite.column_int(stmt, 9))
			track.values[.DateAdded] = i64(sqlite.column_int64(stmt, 10))
			if version >= 1 {
				track.values[.FileDate] = i64(sqlite.column_int64(stmt, 11))
			}
			else {
				track.values[.FileDate] = get_file_date(string(path))
			}

			library_add_track(lib, string(path), track)
		}
	}

	// Cover art
	if version >= 2 {
		stmt: ^sqlite.Statement
		sqlite.prepare_v2(db, "SELECT * FROM cover_art", -1, &stmt, nil)
		defer sqlite.finalize(stmt)

		for {
			if sqlite.step(stmt) != .Row {break}
			path_hash := sqlite.column_int64(stmt, 0)
			cover_path := sqlite.column_text(stmt, 1)
			if cover_path == nil {continue}
			library_add_folder_cover_art_from_hash(lib, u64(path_hash), string(cover_path))
		}

	}
	else {
		log.debug("Scanning track directories for cover art...")

		for dir in lib.path_allocator.dirs {
			library_scan_folder_for_cover_art(lib, path_pool.get_dir_path(dir))
		}
	}

	return
}
