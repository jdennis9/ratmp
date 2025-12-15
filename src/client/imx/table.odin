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

import "core:log"
/*
******************* CURRENTLY UNUSED *******************

Custom implemenation of tables that makes some assumptions that simplifies
the logic and helps a bit with CPU usage. Assumes that rows only contain one line of text
and that the number of rows in always known ahead of time.
*/

import "core:fmt"
import sa "core:container/small_array"

import imgui "src:thirdparty/odin-imgui"

TABLE_MAX_COLUMNS :: 16
TABLE_MAX_COLUMN_NAME_LEN :: 24

/*Table_Flag :: enum {
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

	for &col in sa.slice(&table.columns) {
		col.weight = base_weight
	}
}

begin_table :: proc(
	str_id: cstring, settings_id: cstring,
	columns: []Table_Column, master_column: int,
	row_count: int, flags: Table_Flags, size_arg: [2]f32 = {}
) -> (state: ^Table_State, ok: bool) {
	initialized: bool

	if row_count == 0 do return

	table_id := imgui.GetID(str_id)
	avail_region := imgui.GetContentRegionAvail()
	
	size := [2]f32 {
		size_arg.x != 0 ? size_arg.x : avail_region.x,
		size_arg.y != 0 ? size_arg.y : avail_region.y,
	}
	
	size.x = clamp(size.x, 0, avail_region.x)
	size.y = clamp(size.y, 0, avail_region.y)

	if size.y <= 10 || size.x <= 10 do return
	
	state, initialized = ctx_add_or_get_table(table_id)
	
	if !initialized {
		visible_columns: int
		for col in columns {
			if .DefaultHide not_in col.flags {
				visible_columns += 1
			}
		}

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

		//imgui.SetCursorScreenPos({x_pos - cell_padding.x, y_pos - cell_padding.y})
		//defer imgui.SetCursorScreenPos(old_cursor_pos)

		header_size := [2]f32{width, table.row_height + cell_padding.y}

		imgui.InvisibleButton(text_start, header_size)
		imgui.SameLine()

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
	//drawlist := imgui.GetWindowDrawList()
	//style := imgui.GetStyle()

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
	//style := imgui.GetStyle()
	drawlist := imgui.GetWindowDrawList()
	cursor := _table_begin_row(table)
	defer _table_end_row(table)

	imgui.DrawList_AddText(drawlist, table.cursor, max(u32), cstring(raw_data(str)), cstring(&raw_data(str)[len(str)]))
}

table_row_text_fmt :: proc(table: ^Table_State, $MAX_CHARS: uint, args: ..any) {
	buf: [MAX_CHARS]u8
	table_row_text(table, fmt.bprint(buf[:], ..args))
}

table_row_selectable :: proc(table: ^Table_State, label: string, selected: bool) -> bool {
	assert(table.column_index == table.master_column)
	drawlist := imgui.GetWindowDrawList()
	cursor := _table_begin_row(table)
	defer _table_end_row(table)

	imgui.SetCursorScreenPos(cursor)
	active := imgui.InvisibleButton("##selectable", {table.size.x, table.row_height})
	
	if selected {
		_table_row_bg(table, imgui.GetColorU32(.Header))
	}

	if imgui.IsItemHovered() {
		_table_row_bg(table, imgui.GetColorU32(.HeaderActive))
	}

	imgui.DrawList_AddText(drawlist, table.cursor, max(u32), cstring(raw_data(label)), cstring(&raw_data(label)[len(label)]))

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
*/

Table_State :: struct {
	columns: [TABLE_MAX_COLUMNS]int,
	column_weights: [TABLE_MAX_COLUMNS]f32,
	column_hidden: [TABLE_MAX_COLUMNS]bool,
	visible_column_count: int,
	column_count: int,
	column_index: int,
	size: [2]f32,
	offset: [2]f32,
}

Table_Row :: struct {
	text: string,
	text_width: Maybe(f32),
}

Table_Column :: struct {
	name: cstring,
	flags: imgui.TableColumnFlags,
	rows: []Table_Row,
}

/*begin_table :: proc(str_id: cstring, state: ^Table_State, columns: []Table_Column, size_arg: Maybe([2]f32) = nil) -> bool {
	drawlist := imgui.GetWindowDrawList()
	
	state.column_count = len(columns)
	state.visible_column_count = 0
	state.offset = {}
	
	for col in state.column_hidden[:state.column_count] {
		if !col do state.visible_column_count += 1
	}
	
	for &w in state.column_weights[:state.column_count] {
		w = 1 / f32(state.visible_column_count)
	}
	
	//imgui.BeginChild(str_id, state.size) or_return
	size := size_arg.? or_else imgui.GetContentRegionAvail()
	state.size = size

	offset := f32(0)
	for col, i in columns {
		buf: [TABLE_MAX_COLUMN_NAME_LEN+1]u8
		width := state.column_weights[i] * size.x
		copy(buf[:len(buf-1)], col.name)

		imgui.Selectable(cstring(&buf[0]), false, {}, {width, imgui.GetTextLineHeight()})
		//imgui.SmallButton(cstring(&buf[0])/*, {width, imgui.GetTextLineHeight()}*/)
		if i + 1 != len(columns) do imgui.SameLine()

		offset += width
	}

	return true
}

table_begin_column :: proc(table: ^Table_State, index: int) -> bool {
	table.column_index = index
	table.offset = {}
	if table.column_hidden[index] do return false

	for weight, i in table.column_weights[:table.column_count] {
		if i >= index do break
		if table.column_hidden[i] do continue
		table.offset += weight * table.size.x
	}

	return true
}

table_end_column :: proc(table: ^Table_State) {
}

table_text :: proc(table: ^Table_State, str: string) {
}

table_selectable :: proc(table: ^Table_State, str: string, selected: bool) -> bool {
	return false
}

end_table :: proc(table: ^Table_State) {
	//imgui.EndChild()
}

table_test :: proc() -> bool {
	defer imgui.End()
	imgui.Begin("Table Test") or_return

	@static table: Table_State

	columns := []Table_Column {
		{
			flags = {.Master, .NoHide},
			name = "Title",
		},
		{
			name = "Album",
		},
		{
			name = "Artist",
		},
	}

	if begin_table("Test", &table, columns) {
		end_table(&table)
	}

	return true
}*/

table_show :: proc(str_id: cstring, columns: []Table_Column, scrolling_text_timer: f64) -> bool {
	row_count := len(columns[0].rows)
	master_column := -1
	visible_columns := 0
	window_size := imgui.GetContentRegionAvail()

	// -------------------------------------------------------------------------
	// Content
	// -------------------------------------------------------------------------
	{
		table_flags := imgui.TableFlags_SizingStretchProp | imgui.TableFlags_Resizable
		imgui.BeginTable(str_id, auto_cast len(columns), table_flags) or_return
		defer imgui.EndTable()

		for col in columns {
			imgui.TableSetupColumn(col.name, col.flags)
		}

		imgui.TableSetupScrollFreeze(1, 1)
		imgui.TableHeadersRow()

		imgui.TableNextRow()

		offset := f32(0)
		y_root := imgui.GetTextLineHeight()

		drawlist := imgui.GetWindowDrawList()

		for col, col_index in columns {
			/*if state.column_hidden[col_index] do continue
			width := state.column_weights[col_index] * size.x*/

			//imgui.BeginChild(col.name, {width, imgui.GetContentRegionAvail().y}, {}, {.NoScrollbar, .NoScrollWithMouse})
			//defer imgui.EndChild()

			imgui.TableSetColumnIndex(auto_cast col_index) or_continue
			size := imgui.GetContentRegionAvail()

			//x_padding := imgui.GetStyle().CellPadding.x
			x_padding :: 0
			cursor := imgui.GetCursorScreenPos()

			imgui.PushClipRect(/*drawlist, */cursor + {x_padding, 0}, cursor + size - {x_padding, 0}, true)
			defer imgui.PopClipRect(/*drawlist*/)

			for row, row_index in col.rows {
				scrolling_text(row.text, scrolling_text_timer, size.x, row.text_width, .DrawOffset)
			}

			//offset += width
		}
	}

	return true
}

table_test :: proc(uptime: f64) -> bool {
	@static state: Table_State

	defer imgui.End()
	imgui.Begin("Table Test") or_return

	columns := []Table_Column {
		{
			name = "Title",
			rows = {
				{text = "ESEF"},
				{text = "KETCHUP"},
				{text = "UNCANNY VALLEY"},
			},
		},
		{
			name = "Artist",
			rows = {
				{text = "Billain"},
				{text = "Billain"},
				{text = "Billain"},
			},
		},
		{
			name = "Album",
			rows = {
				{text = ""},
				{text = ""},
				{text = ""},
			},
		}
	}

	table_show("Test Table", columns, uptime)

	return true
}
