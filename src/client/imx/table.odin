package imgui_extensions

import imgui "src:thirdparty/odin-imgui"

Table_Flag :: enum {
	Sortable,
	Resizable,
	Reorderable,
}

Table_Flags :: bit_set[Table_Flag]

Table_Column_Flag :: enum {
	DefaultHide,
	NoHide,
}

Table_Column_Flags :: bit_set[Table_Column_Flag]

Table_Column :: struct {
	name: string,
	flags: Table_Column_Flags,
}

begin_table :: proc(str_id: cstring, settings_id: cstring, columns: []Table_Column, flags: Table_Flags, size: [2]f32 = {}) -> bool {
	return false
}

end_table :: proc() {
}

table_begin_column :: proc(index: int) -> bool {
	return false
}

table_row_text :: proc(str: string) {
}

table_row_selectable :: proc(name: string, selected: bool) -> bool {
	return false
}

table_end_column :: proc() {
}

