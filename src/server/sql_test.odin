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

import "core:testing"
import "core:log"
import "core:fmt"
import "core:strings"
import "core:hash/xxhash"
import "core:time"

import sql "src:thirdparty/odin-sqlite3"
import "src:path_pool"

//@test
test_sql :: proc(t: ^testing.T) {
	tracks: Track_Set
	db: ^sql.Connection
	error: sql.Result_Code

	folder := "D:\\Media\\Music\\Original"

	scan_directory_tracks(folder, &tracks)
	defer track_set_delete(&tracks)

	error = sql.open("db.sqlite", &db)
	log.debug(error)
	defer {
		sql.close(db)
	}

	create_table_statement: cstring = `
	CREATE TABLE tracks (
		id BIGINT PRIMARY KEY,
		path VARCHAR(511),
		title VARCHAR(127),
		artist VARCHAR(127),
		album VARCHAR(127),
		genre VARCHAR(127),
		duration INTEGER,
		track_number INTEGER,
		year INTEGER,
		date_added BIGINT
	)
	`
	exec_error: cstring
	error = sql.exec(db, create_table_statement, nil, nil, &exec_error)
	/*if error != .Ok {
		log.error(error, exec_error)
	}*/

	insert_statement:cstring = `
	INSERT INTO tracks (id, path, title, artist, album, genre, duration, track_number, year, date_added)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`
	stmt: ^sql.Statement
	duration: time.Duration

	defer {
		log.info("Generating database took", time.duration_milliseconds(duration), "ms")
	}

	time.SCOPED_TICK_DURATION(&duration)

	for track, index in tracks.metadata {
		path_buf: [512]u8
		path := path_pool.retrieve_cstring(tracks.path_allocator, tracks.paths[index], path_buf[:])
		path_hash := xxhash.XXH3_64_default(transmute([]u8) string(path))

		sql.prepare_v2(db, insert_statement, -1, &stmt, nil)
		defer sql.finalize(stmt)

		sql.bind_int64(stmt, 1, auto_cast path_hash)
		sql.bind_text(stmt, 2, path, -1, nil)
		sql.bind_text(stmt, 3, strings.unsafe_string_to_cstring(track.values[.Title].(string) or_else ""), -1, nil)
		sql.bind_text(stmt, 4, strings.unsafe_string_to_cstring(track.values[.Artist].(string) or_else ""), -1, nil)
		sql.bind_text(stmt, 5, strings.unsafe_string_to_cstring(track.values[.Album].(string) or_else ""), -1, nil)
		sql.bind_text(stmt, 6, strings.unsafe_string_to_cstring(track.values[.Genre].(string) or_else ""), -1, nil)
		sql.bind_int(stmt, 7, auto_cast(track.values[.Duration].(i64) or_else 0))
		sql.bind_int(stmt, 8, auto_cast(track.values[.TrackNumber].(i64) or_else 0))
		sql.bind_int(stmt, 9, auto_cast(track.values[.Year].(i64) or_else 0))
		sql.bind_int64(stmt, 10, track.values[.DateAdded].(i64) or_else 0)
		sql.step(stmt)
	}
}
