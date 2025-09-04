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

import sa "core:container/small_array"

import imgui "src:thirdparty/odin-imgui"

MAX_TABLES :: 64

Context :: struct {
	table_ids: sa.Small_Array(MAX_TABLES, imgui.ID),
	tables: sa.Small_Array(MAX_TABLES, Table_State),
}

ctx: Context

init :: proc() {
}

@private
ctx_add_or_get_table :: proc(id: imgui.ID) -> (table: ^Table_State, exists: bool) {
	for it, index in sa.slice(&ctx.table_ids) {
		if it == id {
			return sa.get_ptr(&ctx.tables, index), true
		}
	}

	index := sa.len(ctx.tables)

	sa.append(&ctx.table_ids, id)
	sa.append(&ctx.tables, Table_State{})

	return sa.get_ptr(&ctx.tables, index), false
}
