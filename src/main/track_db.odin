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
package main

import "base:runtime"
import "core:strconv"
import "core:slice"
import "core:time"
import "core:log"
import "core:os"
import "core:reflect"
import "core:mem"
import "core:strings"

import sql "src:thirdparty/odin-sqlite3"

VERSION :: 1
VERSION_STATEMENT :: "PRAGMA user_version=1" 

_Column_Type :: enum {
	Int,
	BigInt,
	TinyString,
	ShortString,
	LongString,
}

_Column :: struct {
	name:        string,
	type:        _Column_Type,
	field:       reflect.Struct_Field,
	min_version: int,
}


_COLUMN_TYPE_NAME := [_Column_Type]string {
	.Int         = "INTEGER",
	.BigInt      = "BIGINT",
	.TinyString  = "VARCHAR(31)",
	.ShortString = "VARCHAR(127)",
	.LongString  = "VARCHAR(511)",
}

sfield :: reflect.struct_field_by_name

_Track_DB_Model :: struct {
	path_hash: i64,
	url: string,
	protocol: string,

	format,
	artist,
	album,
	genre,
	title: string,

	duration_seconds,
	track_no,
	release_year,
	bitrate_kbps,
	channels,
	samplerate: int,

	file_size,
	file_date,
	date_added: i64,
}

_track_to_db_model :: proc(l: Library, t: Track, allocator: mem.Allocator) -> (model: _Track_DB_Model, error: Error) {
	return _Track_DB_Model {
		path_hash        = auto_cast stable_hash_string_64(t.url),
		protocol         = reflect.enum_name_from_value(t.protocol) or_else "File",
		url              = t.url,
		format           = reflect.enum_name_from_value(t.format) or_else "",
		artist           = library_join_track_group_names_to_allocator(l, t.artists, .Artist, allocator),
		album            = library_get_album_name(l, t.album),
		genre            = library_join_track_group_names_to_allocator(l, t.genres, .Genre, allocator),
		title            = t.title,
		duration_seconds = auto_cast t.duration_seconds,
		track_no         = auto_cast t.track_no,
		release_year     = auto_cast t.release_year,
		bitrate_kbps     = auto_cast t.bitrate_kbps,
		channels         = auto_cast t.channels,
		samplerate       = auto_cast t.samplerate,
		file_size        = auto_cast t.file_size,
		file_date        = time.to_unix_seconds(t.file_date),
		date_added       = time.to_unix_seconds(t.date_added),
	}, nil
}

_track_from_db_model :: proc(t: _Track_DB_Model, allocator: mem.Allocator) -> (ret: Track_Data, error: Error) {
	return Track_Data {
		protocol         = reflect.enum_from_name(Track_Protocol, t.protocol) or_else .File,
		url              = strings.clone(t.url, allocator) or_return,
		format           = reflect.enum_from_name(Audio_File_Format, t.format) or_else .Wav,
		artist           = strings.clone(t.artist, allocator) or_return,
		album            = strings.clone(t.album, allocator) or_return,
		genre            = strings.clone(t.genre, allocator) or_return,
		title            = strings.clone(t.title, allocator) or_return,
		duration_seconds = auto_cast t.duration_seconds,
		track_no         = auto_cast t.track_no,
		release_year     = auto_cast t.release_year,
		bitrate_kbps     = auto_cast t.bitrate_kbps,
		channels         = auto_cast t.channels,
		samplerate       = auto_cast t.samplerate,
		file_size        = auto_cast t.file_size,
		file_date        = time.unix(t.file_date, 0),
		date_added       = time.unix(t.date_added, 0),
	}, nil
}

_check :: proc(sr: sql.Result_Code, msg: cstring = nil) -> Error {
	if sr != .Ok && sr != .Done && sr != .Row {
		if msg == nil do log.error(sr)
		log.error(sr, ": ", msg, sep="")
		return Custom_Error.ThirdParty
	}

	return nil
}

_get_columns :: proc() -> []_Column {
	s := []_Column {
		// column name, type, field info, minimum version
		{"id",         .BigInt,      sfield(_Track_DB_Model, "path_hash"),        1},
		{"url",        .LongString,  sfield(_Track_DB_Model, "url"),              1},
		{"protocol",   .TinyString,  sfield(_Track_DB_Model, "protocol"),         1},
		{"format",     .TinyString,  sfield(_Track_DB_Model, "format"),           1},
		{"artist",     .ShortString, sfield(_Track_DB_Model, "artist"),           1},
		{"album",      .ShortString, sfield(_Track_DB_Model, "album"),            1},
		{"genre",      .ShortString, sfield(_Track_DB_Model, "genre"),            1},
		{"title",      .ShortString, sfield(_Track_DB_Model, "title"),            1},
		{"duration",   .Int,         sfield(_Track_DB_Model, "duration_seconds"), 1},
		{"track",      .Int,         sfield(_Track_DB_Model, "track_no"),         1},
		{"year",       .Int,         sfield(_Track_DB_Model, "release_year"),     1},
		{"bitrate",    .Int,         sfield(_Track_DB_Model, "bitrate_kbps"),     1},
		{"channels",   .Int,         sfield(_Track_DB_Model, "channels"),         1},
		{"samplerate", .Int,         sfield(_Track_DB_Model, "samplerate"),       1},
		{"file_size",  .BigInt,      sfield(_Track_DB_Model, "file_size"),        1},
		{"file_date",  .BigInt,      sfield(_Track_DB_Model, "file_date"),        1},
		{"date_added", .BigInt,      sfield(_Track_DB_Model, "date_added"),       1},
	}

	return slice.clone(s)
}

@private
track_db_save :: proc(l: Library, path: string) -> Error {
	TIME_SCOPE("Save library to SQL database")

	columns := _get_columns()
	defer delete(columns)
	
	path_cstring := strings.clone_to_cstring(path)
	defer delete(path_cstring)
	
	//os.remove(path) or_return

	// --------------------------------------------------------------------------
	// Open DB
	// --------------------------------------------------------------------------
	db: ^sql.Connection
	_check(sql.open(path_cstring, &db)) or_return
	defer sql.close(db)
	
	// --------------------------------------------------------------------------
	// Create tracks table
	// --------------------------------------------------------------------------
	{
		exec_error: cstring
		b: strings.Builder

		sql.exec(db, "DROP TABLE tracks", nil, nil, nil)

		defer strings.builder_destroy(&b)

		strings.write_string(&b, "CREATE TABLE tracks (\n")
		for col, i in columns {
			strings.write_string(&b, "\t")
			strings.write_string(&b, col.name)
			strings.write_string(&b, " ")
			strings.write_string(&b, _COLUMN_TYPE_NAME[col.type])
			if i != len(columns)-1 do strings.write_string(&b, ",\n")
			else do strings.write_string(&b, "\n")
		}
		strings.write_string(&b, ")")

		_check(sql.exec(db, strings.to_cstring(&b), nil, nil, &exec_error), exec_error)
	}

	// --------------------------------------------------------------------------
	// Create cover art table
	// --------------------------------------------------------------------------
	{
		exec_error: cstring
		sql.exec(db, "DROP TABLE cover_art", nil, nil, nil)
		statement :: `CREATE TABLE cover_art (folder_hash BIGINT, cover_path VARCHAR(512))`
		_check(sql.exec(db, statement, nil, nil, &exec_error), exec_error)
	}

	// --------------------------------------------------------------------------
	// Set up temporary arena
	// --------------------------------------------------------------------------
	temp_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temp_arena)
	defer mem.dynamic_arena_destroy(&temp_arena)
	temp_allocator := mem.dynamic_arena_allocator(&temp_arena)

	// --------------------------------------------------------------------------
	// Convert tracks to db model
	// --------------------------------------------------------------------------
	tracks: [dynamic]_Track_DB_Model
	defer delete(tracks)

	{
		for _, track in l.tracks {
			append(
				&tracks,
				_track_to_db_model(l, track, temp_allocator) or_continue
			)
		}
	}
	
	_check(sql.exec(db, VERSION_STATEMENT, nil, nil, nil)) or_return
	_check(sql.exec(db, "BEGIN TRANSACTION", nil, nil, nil)) or_return
	defer _check(sql.exec(db, "END TRANSACTION", nil, nil, nil))

	// --------------------------------------------------------------------------
	// Write track rows
	// --------------------------------------------------------------------------
	{
		b: strings.Builder
		defer strings.builder_destroy(&b)
		
		// Build insert string
		// @TODO: Insert into columns by name
		strings.write_string(&b, "INSERT INTO tracks VALUES (")
		for _, i in columns {
			if i != len(columns)-1 do strings.write_string(&b, "?, ")
			else do strings.write_string(&b, "?")
		}
		strings.write_string(&b, ")")
		log.debug(strings.to_string(b))
		
		prepare_statement := strings.to_cstring(&b) or_return
		
		for track in tracks {
			stmt: ^sql.Statement

			_check(sql.prepare_v2(db, prepare_statement, -1, &stmt, nil)) or_continue
			defer sql.finalize(stmt)

			for col, i in columns {
				f := reflect.struct_field_value(track, col.field)
				bind_index := i32(i + 1)

				switch col.type {
					case .Int:
						v := f.(int)
						sql.bind_int(stmt, bind_index, auto_cast v)
					case .BigInt:
						v := f.(i64)
						sql.bind_int64(stmt, bind_index, auto_cast v)
					case .TinyString, .ShortString, .LongString:
						v := f.(string)
						sql.bind_text(stmt, bind_index, cstring(raw_data(v)), auto_cast len(v), {})
				}
			}

			_check(sql.step(stmt))
		}

	}

	// --------------------------------------------------------------------------
	// Write cover art rows
	// --------------------------------------------------------------------------
	{
		log.debug("Writing cover art to DB...")

		for folder_hash, art_path in l.folder_cover_art {
			stmt: ^sql.Statement
			_check(sql.prepare_v2(db, "INSERT INTO cover_art VALUES (?, ?)", -1, &stmt, nil))
			defer sql.finalize(stmt)

			sql.bind_int64(stmt, 1, auto_cast folder_hash)
			sql.bind_text(stmt, 2, cstring(raw_data(art_path)), auto_cast len(art_path), {})

			_check(sql.step(stmt))
		}
	}
	
	return nil
}

@private
track_db_load :: proc(
	l: ^Library, path: string
) -> Error {
	TIME_SCOPE("Load SQL library")

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)

	columns := _get_columns()
	defer delete(columns)

	sr: sql.Result_Code
	version: int
	
	path_cstring := strings.clone_to_cstring(path)
	defer delete(path_cstring)
	
	// --------------------------------------------------------------------------
	// Open DB
	// --------------------------------------------------------------------------
	db: ^sql.Connection
	sr = sql.open(path_cstring, &db)
	_check(sr) or_return
	defer sql.close(db)

	// --------------------------------------------------------------------------
	// Set up temporary arena
	// --------------------------------------------------------------------------
	temp_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temp_arena, block_size=128<<10)
	defer mem.dynamic_arena_destroy(&temp_arena)
	temp_allocator := mem.dynamic_arena_allocator(&temp_arena)

	// --------------------------------------------------------------------------
	// Get version
	// --------------------------------------------------------------------------
	set_version :: proc "c" (ctx: rawptr, argc: i32, argv: [^]cstring, col_name: [^]cstring) -> i32 {
		if argc != 1 do return 0
		context = runtime.default_context()
		version := cast(^i32) ctx
		version^ = cast(i32) (strconv.parse_i64(string(argv[0])) or_else 0)
		return 0
	}

	{
		user_version: i32
		_check(sql.exec(db, "PRAGMA user_version", set_version, &user_version, nil))
		version = auto_cast user_version
	}


	// --------------------------------------------------------------------------
	// Cover art
	// --------------------------------------------------------------------------
	{
		stmt: ^sql.Statement
		_check(sql.prepare_v2(db, "SELECT * from cover_art", -1, &stmt, nil))

		for {
			folder_hash: i64
			cover_path: cstring

			result := sql.step(stmt)
			_check(result)
			if result != .Row do break

			folder_hash = sql.column_int64(stmt, 0)
			cover_path = sql.column_text(stmt, 1)

			if cover_path != nil {
				l.folder_cover_art[u64(folder_hash)] = strings.clone(string(cover_path), l.allocators.track_data)
			}
			else {
				l.folder_cover_art[u64(folder_hash)] = ""
			}
		}
	}

	// --------------------------------------------------------------------------
	// Load tracks in model format
	// --------------------------------------------------------------------------
	
	models := make_dynamic_array_len_cap([dynamic]_Track_DB_Model, 0, 2048)
	defer delete(models)
	{
		TIME_SCOPE("DB table -> tracks")

		stmt: ^sql.Statement
		defer sql.finalize(stmt)

		// @TODO: Select columns by name
		_check(sql.prepare_v2(db, "SELECT * FROM tracks", -1, &stmt, nil))
		
		for {
			model: _Track_DB_Model
			result := sql.step(stmt)
			_check(result)
			if result != .Row do break

			col_index: i32 = 0

			for col in columns {
				if version < col.min_version do continue
				if version > VERSION do continue

				f := reflect.struct_field_value(model, col.field)

				switch col.type {
				case .Int:
					assert(col.field.type.id == int)
					v := sql.column_int(stmt, col_index)
					(cast(^int) f.data)^ = auto_cast v
				case .BigInt:
					assert(col.field.type.id == i64)
					v := sql.column_int64(stmt, col_index)
					(cast(^i64) f.data)^ = auto_cast v
				case .TinyString, .ShortString, .LongString:
					assert(col.field.type.id == string)
					v := sql.column_text(stmt, col_index)
					(cast(^string) f.data)^ = strings.clone(string(v), temp_allocator)
				}

				col_index += 1
			}

			append(&models, model)
		}
	}

	// --------------------------------------------------------------------------
	// Convert models -> tracks for library
	// --------------------------------------------------------------------------
	{
		TIME_SCOPE("Models -> tracks -> library")
		for model in models {
			path_hash := cast(u64) model.path_hash
			_, exists := l.url_hash_map[path_hash]

			// Update the track?
			if exists do continue

			track := _track_from_db_model(model, allocator) or_continue

			//handle := handle_map.add(track_map, track) or_continue
			library_add_track(l, track)
		}
	}

	return nil
}
