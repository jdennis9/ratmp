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
