package imgui_extensions

/*
Custom implemenation of tables that makes some assumptions that simplifies
the logic and helps a bit with CPU usage. Assumes that rows only contain one line of text
and that the number of rows in always known ahead of time.
*/

import "core:fmt"
import "core:log"
import sa "core:container/small_array"

import imgui "src:thirdparty/odin-imgui"

TABLE_MAX_COLUMNS :: 16
TABLE_MAX_COLUMN_NAME_LEN :: 24

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

Table_Column_State :: struct {
	name: sa.Small_Array(TABLE_MAX_COLUMN_NAME_LEN, u8),
	weight: f32,
	flags: Table_Column_Flags,
	hidden: bool,
}

Table_State :: struct {
	columns: sa.Small_Array(TABLE_MAX_COLUMNS, Table_Column_State),
	column_order: [TABLE_MAX_COLUMNS]int,
	flags: Table_Flags,
	row_index: int,
	column_index: int,
	master_column: int,
	cursor_start: [2]f32,
	size: [2]f32,
	cursor: [2]f32,
	row_height: f32,
	current_column_width: f32,
	row_count: int,

	display_start: int,
	display_end: int,
}

@private
_table_calc_column_weights :: proc(table: ^Table_State) {
	visible_columns: int
	for col in sa.slice(&table.columns) {
		if !col.hidden {
			visible_columns += 1
		}
	}

	base_weight := 1.0 / f32(visible_columns)

	for &col, index in sa.slice(&table.columns) {
		col.weight = base_weight
	}
}

begin_table :: proc(
	str_id: cstring, settings_id: cstring,
	columns: []Table_Column, master_column: int,
	row_count: int, flags: Table_Flags, size_arg: [2]f32 = {}
) -> (state: ^Table_State, ok: bool) {
	initialized: bool

	table_id := imgui.GetID(str_id)
	avail_region := imgui.GetContentRegionAvail()
	
	size := [2]f32 {
		size_arg.x != 0 ? size_arg.x : avail_region.x,
		size_arg.y != 0 ? size_arg.y : avail_region.y,
	}
	
	size.x = clamp(size.x, 0, avail_region.x)
	size.y = clamp(size.y, 0, avail_region.y)
	
	state, initialized = ctx_add_or_get_table(table_id)
	
	if !initialized {
		visible_columns: int
		for col in columns {
			if .DefaultHide not_in col.flags {
				visible_columns += 1
			}
		}

		base_weight := 1.0 / f32(visible_columns)
		sa.resize(&state.columns, len(columns))
		
		for &col, index in sa.slice(&state.columns) {
			params := columns[index]
			col.flags = params.flags
			if .DefaultHide in params.flags {
				col.hidden = true
			}
			state.column_order[index] = index

			assert(len(params.name) < TABLE_MAX_COLUMN_NAME_LEN)
			sa.resize(&col.name, len(params.name))
			for &c in col.name.data[:] {c = 0}
			copy(sa.slice(&col.name), params.name)
		}

		_table_calc_column_weights(state)
	}
	
	state.master_column = master_column
	state.row_count = row_count
	state.row_index = -1
	state.column_index = -1
	state.flags = flags

	// @TODO: Clip lines
	state.display_start = 0
	state.display_end = row_count
	
	if imgui.BeginChild(str_id, size) {
		style := imgui.GetStyle()
		drawlist := imgui.GetWindowDrawList()
		state.cursor_start = imgui.GetCursorScreenPos()
		state.cursor = state.cursor_start
		state.size = size
		state.row_height = imgui.GetTextLineHeight() + (2 * style.CellPadding.y)

		// Draw column separators
		
		x_pos := state.cursor_start.x
		y_pos := state.cursor_start.y + imgui.GetScrollY()
	
		// Draw column separators
		for column_index in 0..<(sa.len(state.columns)-1) {
			col := sa.get(state.columns, state.column_order[column_index])
			if col.hidden {continue}
			x_pos += col.weight * size.x

			line_start := [2]f32{x_pos - style.CellPadding.x, y_pos}
			line_end := [2]f32{x_pos - style.CellPadding.x, y_pos + size.y}

			imgui.DrawList_AddLine(drawlist, line_start, line_end, imgui.GetColorU32(.TableBorderLight))

			// Resize behaviour
			/*if state.column_order[column_index] > 0 && .Resizable in flags {
				imgui.PushIDInt(auto_cast column_index)
				defer imgui.PopID()

				left_column := sa.get_ptr(&state.columns, state.column_order[column_index - 1])
				right_column := &col

				grab_size := [2]f32{4, state.size.y}
				grab_pos := [2]f32{x_pos, y_pos}
				grab_pos.x -= grab_size.x
				old_cursor := imgui.GetCursorScreenPos()
				defer imgui.SetCursorScreenPos(old_cursor)

				hovered, held: bool

				imgui.SetCursorScreenPos(grab_pos)
				imgui.InvisibleButton("##column_resize", grab_size)

				hovered = imgui.IsItemHovered()
				held = imgui.IsItemActive()

				if held {
					weight_offset := f32(0)
					cursor_rel_x_pos := (imgui.GetMousePos().x - state.cursor_start.x) / state.size.x

					for i in state.column_order {
						if i == column_index {break}
						c := sa.get(state.columns, i)
						weight_offset += c.weight
					}

					left_column.weight = cursor_rel_x_pos - weight_offset

					imgui.SetMouseCursor(.ResizeEW)
					imgui.DrawList_AddLine(drawlist, line_start, line_end, imgui.GetColorU32(.ResizeGripActive))
				}
				else if hovered {
					imgui.SetMouseCursor(.ResizeEW)
					imgui.DrawList_AddLine(drawlist, line_start, line_end, imgui.GetColorU32(.ResizeGripHovered))
				}
			}*/
		}

		// Resize behaviour
		if .Resizable in flags {
			x_pos = state.cursor_start.x + (sa.get(state.columns, state.column_order[0]).weight * state.size.x)
			accum_weight := f32(0)

			for left_column_index, order_index in state.column_order[:sa.len(state.columns)] {
				hovered, held: bool
				left_column := sa.get_ptr(&state.columns, left_column_index)
				if left_column.hidden {continue}
				if order_index+1 >= sa.len(state.columns) {continue}
				right_column := sa.get_ptr(&state.columns, state.column_order[order_index + 1])

				imgui.PushIDInt(auto_cast left_column_index)
				defer imgui.PopID()

				line_start := [2]f32{x_pos - style.CellPadding.x, y_pos}
				line_end := [2]f32{x_pos - style.CellPadding.x, y_pos + size.y}
				grab_size := [2]f32{4, state.size.y}
				grab_pos := [2]f32{x_pos, y_pos}
				grab_pos.x -= grab_size.x

				imgui.SetCursorScreenPos(grab_pos)
				imgui.InvisibleButton("##column_resize", grab_size)

				hovered = imgui.IsItemHovered()
				held = imgui.IsItemActive()

				if held {
					cursor_rel_x_pos := (imgui.GetMousePos().x - state.cursor_start.x) / state.size.x
					old_weight := left_column.weight
					left_column.weight = cursor_rel_x_pos - accum_weight
					right_column.weight += old_weight - left_column.weight
					imgui.SetMouseCursor(.ResizeEW)
					imgui.DrawList_AddLine(drawlist, line_start, line_end, imgui.GetColorU32(.ResizeGripActive))
				}
				else if hovered {
					imgui.SetMouseCursor(.ResizeEW)
					imgui.DrawList_AddLine(drawlist, line_start, line_end, imgui.GetColorU32(.ResizeGripHovered))
				}

				x_pos += left_column.weight * state.size.x
				accum_weight += left_column.weight
			}
		}
		
		cell_padding := style.CellPadding
		bg_color := imgui.GetColorU32(.TableRowBg)
		bg_color_alt := imgui.GetColorU32(.TableRowBgAlt)
		border_color := imgui.GetColorU32(.TableBorderLight)

		// Cell backgrounds
		for row_index in state.display_start..<state.display_end {
			pmin := [2]f32{state.cursor_start.x - cell_padding.x, state.cursor_start.y + f32(row_index) * state.row_height - cell_padding.y}
			pmax := pmin + [2]f32{state.size.x, state.row_height}
			color := row_index % 2 != 0 ? bg_color_alt : bg_color

			imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, color)
		}

		// Cell borders
		for row_index in state.display_start..<state.display_end {
			pmin := [2]f32{state.cursor_start.x - cell_padding.x, state.cursor_start.y + f32(row_index) * state.row_height - cell_padding.y}
			pmax := pmin + [2]f32{state.size.x, 0}
			imgui.DrawList_AddLine(drawlist, pmin, pmax, border_color)
		}

		state.cursor = state.cursor_start

		return state, true
	}

	return nil, false
}

end_table :: proc(table: ^Table_State) {
	style := imgui.GetStyle()
	drawlist := imgui.GetWindowDrawList()

	size := table.size
	y_pos := table.cursor_start.y + imgui.GetScrollY()
	x_pos := table.cursor_start.x
	cell_padding := style.CellPadding

	// Draw header bg
	imgui.DrawList_AddRectFilled(
		drawlist,
		{x_pos - cell_padding.x, y_pos - cell_padding.y},
		{x_pos + size.x, y_pos + table.row_height},
		imgui.GetColorU32(.TableHeaderBg),
	)

	// Draw header text
	for i in 0..<sa.len(table.columns) {
		col := sa.get(table.columns, table.column_order[i])
		if col.hidden {continue}
		width := col.weight * size.x
		text_start := cstring(sa.get_ptr(&col.name, 0))
		text_end := cstring(sa.get_ptr(&col.name, sa.len(col.name)))

		old_cursor_pos := imgui.GetCursorScreenPos()

		imgui.SetCursorScreenPos({x_pos - cell_padding.x, y_pos - cell_padding.y})
		defer imgui.SetCursorScreenPos(old_cursor_pos)

		header_size := [2]f32{width, table.row_height + cell_padding.y}

		imgui.InvisibleButton(text_start, header_size)

		if imgui.IsItemHovered() {
			pmin := [2]f32{x_pos, y_pos} - cell_padding
			pmax := pmin + header_size
			imgui.DrawList_AddRectFilled(drawlist, pmin, pmax, imgui.GetColorU32(.HeaderActive))
		}

		if imgui.BeginPopupContextItem() {
			for &it in sa.slice(&table.columns) {
				if .NoHide not_in it.flags {
					shown := !it.hidden
					if imgui.MenuItemBoolPtr(cstring(&it.name.data[0]), nil, &shown) {
						it.hidden = !shown
						_table_calc_column_weights(table)
					}
				}
			}
			imgui.EndPopup()
		}

		imgui.DrawList_AddText(drawlist, 
			{x_pos, y_pos},
			imgui.GetColorU32(.Text),
			text_start,
			text_end
		)

		x_pos += width
	}

	// Draw header underline
	imgui.DrawList_AddLine(
		drawlist,
		{table.cursor_start.x, y_pos + table.row_height},
		{table.cursor_start.x + table.size.x, y_pos + table.row_height},
		imgui.GetColorU32(.TableBorderLight),
	)

	imgui.EndChild()
}

table_begin_column :: proc(table: ^Table_State, index: int) -> bool {
	table.column_index = index
	column := sa.get(table.columns, index)
	if column.hidden {return false}
	table.row_index = 0
	table.cursor = table.cursor_start

	for i in table.column_order[:sa.len(table.columns)] {
		if i == index {break}
		col := sa.get(table.columns, i)
		if !col.hidden {
			table.cursor.x += col.weight * table.size.x
		}
	}

	table.current_column_width = column.weight * table.size.x

	imgui.PushIDInt(auto_cast index)

	cell_padding := imgui.GetStyle().CellPadding

	imgui.DrawList_PushClipRect(
		imgui.GetWindowDrawList(),
		{table.cursor.x, table.cursor_start.y},
		{table.cursor.x + table.current_column_width - cell_padding.x, table.cursor_start.y + table.size.y + imgui.GetScrollY()},
		true
	)

	return true
}

table_end_column :: proc(table: ^Table_State) {
	imgui.DrawList_PopClipRect(imgui.GetWindowDrawList())
	imgui.PopID()
}

table_row_push_tree :: proc(table: ^Table_State, label: string) {
}

table_row_pop_tree :: proc(table: ^Table_State) {
}

@require_results @private
_table_begin_row :: proc(table: ^Table_State) -> (cursor: [2]f32) {

	/*if table.column_index == table.master_column {
		if table.row_index % 2 != 0 {
			_table_row_bg(table, imgui.GetColorU32(.TableRowBgAlt))
		}
		else {
			_table_row_bg(table, imgui.GetColorU32(.TableRowBg))
		}
	}*/

	imgui.PushIDInt(auto_cast table.row_index)

	return table.cursor
}

@private
_table_end_row :: proc(table: ^Table_State) {
	drawlist := imgui.GetWindowDrawList()
	style := imgui.GetStyle()

	table.row_index += 1
	table.cursor.y += table.row_height

	/*if table.column_index == table.master_column {
		imgui.DrawList_AddLine(
			drawlist,
			{table.cursor_start.x, table.cursor.y - style.CellPadding.y},
			{table.cursor_start.x + table.size.x, table.cursor.y - style.CellPadding.y},
			imgui.GetColorU32(.TableBorderLight),
		)

		imgui.Dummy({table.size.y, table.row_height})
	}*/

	imgui.PopID()
}

@private
_table_row_bg :: proc(table: ^Table_State, color: u32) {
	padding := imgui.GetStyle().CellPadding
	drawlist := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(
		drawlist,
		{table.cursor_start.x - padding.x, table.cursor.y - padding.y},
		{table.cursor_start.x + table.size.x, table.cursor.y + table.row_height},
		color
	)
}

table_row_text :: proc(table: ^Table_State, str: string) {
	style := imgui.GetStyle()
	drawlist := imgui.GetWindowDrawList()
	cursor := _table_begin_row(table)
	imgui.DrawList_AddText(drawlist, table.cursor, max(u32), cstring(raw_data(str)), cstring(&raw_data(str)[len(str)]))
	_table_end_row(table)
}

table_row_text_fmt :: proc(table: ^Table_State, $MAX_CHARS: uint, args: ..any) {
	buf: [MAX_CHARS]u8
	table_row_text(table, fmt.bprint(buf[:], ..args))
}

table_row_selectable :: proc(table: ^Table_State, label: string, selected: bool) -> bool {
	assert(table.column_index == table.master_column)
	style := imgui.GetStyle()
	drawlist := imgui.GetWindowDrawList()
	cursor := _table_begin_row(table)

	imgui.SetCursorScreenPos(cursor)
	active := imgui.InvisibleButton("##selectable", {table.size.x, table.row_height})
	
	if selected {
		_table_row_bg(table, imgui.GetColorU32(.Header))
	}

	if imgui.IsItemHovered() {
		_table_row_bg(table, imgui.GetColorU32(.HeaderActive))
	}

	imgui.DrawList_AddText(drawlist, table.cursor, max(u32), cstring(raw_data(label)), cstring(&raw_data(label)[len(label)]))

	_table_end_row(table)
	return active
}


table_test :: proc() {
	if !imgui.Begin("Table Test") {imgui.End(); return}
	defer imgui.End()

	columns := []Table_Column {
		{
			flags = {.NoHide},
			name = "Title",
		},
		{
			flags = {.DefaultHide},
			name = "Genre",
		},
		{
			name = "Artist",
		},
		{
			name = "Album",
		},
	}

	rows := 64

	if table, ok := begin_table("##table_test", "track_table", columns, 0, rows, {.Resizable, .Reorderable}); ok {
		table.column_order[0] = 1
		table.column_order[1] = 0

		@static sel_row := 0
		if table_begin_column(table, 0) {
			for i in table.display_start..<table.display_end {
				if table_row_selectable(table, "Title", i == sel_row) {
					sel_row = i
				}
			}
			table_end_column(table)
		}

		if table_begin_column(table, 2) {
			for i in table.display_start..<table.display_end {
				table_row_text_fmt(table, 32, "Artist", i)
			}
			table_end_column(table)
		}

		if table_begin_column(table, 3) {
			for _ in table.display_start..<table.display_end {
				table_row_text(table, "Album")
			}
			table_end_column(table)
		}

		end_table(table)
	}
}
