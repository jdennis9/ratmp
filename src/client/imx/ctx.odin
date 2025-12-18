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
package imgui_extensions

import "core:strings"
import "core:strconv"
import "base:runtime"
import "core:mem"
import sa "core:container/small_array"

import imgui "src:thirdparty/odin-imgui"

MAX_TABLES :: 64
TABLE_SETTINGS_TYPE_NAME :: "CUSTOM_TABLE"

Table_Column_Settings :: struct {
	name: cstring,
	hidden: bool,
}

Table_Settings :: struct {
	id: imgui.ID,
}

Context :: struct {
	ctx: runtime.Context,
	tables: map[imgui.ID]Table_State,
}

ctx: Context

init :: proc() {
	ctx.ctx = context

	table_settings_handler := imgui.SettingsHandler {
		//ReadInitFn = _imgui_table_settings_init,
		ReadOpenFn = _imgui_table_settings_open,
		ReadLineFn = _imgui_table_settings_read_line,
		WriteAllFn = _imgui_table_settings_write,
		TypeName = TABLE_SETTINGS_TYPE_NAME,
		TypeHash = imgui.cImHashStr(TABLE_SETTINGS_TYPE_NAME),
	}

	imgui.AddSettingsHandler(&table_settings_handler)
}

@(private="file")
_imgui_table_settings_open :: proc "c" (
	_: ^imgui.Context, handler: ^imgui.SettingsHandler, name: cstring
) -> rawptr {
	context = ctx.ctx
	id := cast(imgui.ID) (strconv.parse_int(string(name)) or_else 0)
	if id == 0 do return nil

	t, _ := ctx_add_or_get_table(id)
	for i in 0..<TABLE_MAX_COLUMNS do t.column_order[i] = i
	t.settings_loaded = true

	return t
}

@(private="file")
_imgui_table_settings_read_line :: proc "c" (
	_: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line_cstring: cstring
) {
	context = ctx.ctx
	line := string(line_cstring)
	table := cast(^Table_State) entry

	if strings.starts_with(line, "Column") {
		parts := strings.split(line, " ")
		defer delete(parts)

		if len(parts) < 3 do return

		column_index := strconv.parse_int(parts[1]) or_else -1
		if column_index < 0 || column_index >= TABLE_MAX_COLUMNS do return
		column := &table.columns[column_index]

		for kv_pair in parts[2:] {
			kv := strings.split(kv_pair, "=")
			defer delete(kv)
			if len(kv) != 2 do continue
			if kv[0] == "Hidden" {
				column.hidden = (strconv.parse_int(kv[1]) or_else 0) >= 1
			}
			else if kv[0] == "Weight" {
				column.weight = strconv.parse_f32(kv[1]) or_else 0
				if column.weight <= 0 || column.weight >= 1 do column.hidden = true
			}
		}
	}
}

@(private="file")
_imgui_table_settings_write :: proc "c" (
	_: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
) {
	for table_id, &table in ctx.tables {
		imgui.TextBuffer_appendf(out_buf, "[%s][0x%x]\n", cstring(TABLE_SETTINGS_TYPE_NAME), u32(table_id))
		
		imgui.TextBuffer_append(out_buf, "Order=")
		for i in 0..<table.column_count {
			order := table.column_order[i]
			imgui.TextBuffer_appendf(out_buf, "%d", i32(order))
			if i + 1 != table.column_count {
				imgui.TextBuffer_append(out_buf, ",")
			}
		}
		imgui.TextBuffer_append(out_buf, "\n")

		for column, index in table.columns[:table.column_count] {
			imgui.TextBuffer_appendf(
				out_buf, "Column %d Hidden=%d Weight=%f\n", i32(index), i32(column.hidden), column.weight
			)
		}
	}
}

@private
ctx_add_or_get_table :: proc(id: imgui.ID) -> (table: ^Table_State, exists: bool) {
	/*for it, index in sa.slice(&ctx.table_ids) {
		if it == id {
			return sa.get_ptr(&ctx.tables, index), true
		}
	}

	index := sa.len(ctx.tables)

	sa.append(&ctx.table_ids, id)
	sa.append(&ctx.tables, Table_State{})

	return sa.get_ptr(&ctx.tables, index), false*/
	
	table = &ctx.tables[id]
	if table == nil {
		ctx.tables[id] = {}
		table = &ctx.tables[id]
		return
	}
	else {
		exists = true
		return
	}
}
