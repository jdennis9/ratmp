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

import "core:math/linalg"
import "src:licenses"
import "core:log"
/*
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

Table_Row_ID :: u64

Table_Sort_Order :: enum u8 {
	None,
	Ascending,
	Descending,
}

Table_Column :: struct {
	weight: f32,
	hidden: bool,
	sort_order: Table_Sort_Order,
}

Table_State :: struct {
	columns: [TABLE_MAX_COLUMNS]Table_Column,
	column_order: [TABLE_MAX_COLUMNS]int,
	column_count: int,
	need_distribute_weights: bool,
	settings_loaded: bool,
	resize_start: f32,
	resize_column: int,
}

Table_Result :: struct {
	left_clicked_row: Maybe(Table_Row_ID),
	middle_clicked_row: Maybe(Table_Row_ID),
	sort_by_column: Maybe(int),
	sort_order: Table_Sort_Order,
}

Table_Row_Content :: struct {
	text: string,
	text_width: Maybe(f32),
}

Table_Column_Flag :: enum {DefaultHide, NoHide}
Table_Column_Flags :: bit_set[Table_Column_Flag]

Table_Column_Info :: struct {
	name: cstring,
	flags: Table_Column_Flags,
	rows: []Table_Row_Content,
}

@(private="file")
_table_init :: proc(t: ^Table_State, columns: []Table_Column_Info) {
	t.column_count = len(columns)

	log.debug("Init table")

	if t.settings_loaded {
		// Validate weights
		total_weight: f32
		have_visible_column: bool

		for &col in t.columns[:t.column_count] {
			if col.hidden do continue
			total_weight += col.weight
			have_visible_column = true
		}

		if total_weight != 1 do _table_distribute_weights(t)
	}
	else {
		for i in 0..<len(columns) {
			col := columns[i]
			t.column_order[i] = i
			if .DefaultHide in col.flags do t.columns[i].hidden = true
		}
		_table_distribute_weights(t)
	}

}

@(private="file")
_table_count_visible_columns :: proc(t: ^Table_State) -> (count: int) {
	for col in t.columns[:t.column_count] {
		if !col.hidden do count += 1
	}
	return
}

@(private="file")
_table_distribute_weights :: proc(t: ^Table_State) {
	visible_columns: f32

	visible_columns = f32(_table_count_visible_columns(t))

	for &c in t.columns[:t.column_count] {
		c.weight = 1 / visible_columns
	}
}

Table_Row :: struct {
	id: Table_Row_ID,
	selected: bool,
}

Table_Display_Info :: struct {
	highlight_row_id: Table_Row_ID,
	highlight_color: u32,
	columns: []Table_Column_Info,
	rows: []Table_Row,
	context_menu_id: imgui.ID,
}

@(private="file")
_table_selection_logic :: proc(rows: []Table_Row, row_index: int, keep_selection: bool) {
	row := &rows[row_index]

	ctrl := imgui.IsKeyDown(.ImGuiMod_Ctrl)
	shift := imgui.IsKeyDown(.ImGuiMod_Shift)

	// -------------------------------------------------------------
	// Selection logic
	// -------------------------------------------------------------
	if !ctrl && !shift {
		if !keep_selection || !row.selected {
			for &r in rows {r.selected = false}
		}
		row.selected = true
	}
	else if (ctrl && shift) || shift {
		lo := max(int)
		hi := -1
		for r, i in rows {
			if r.selected {
				if i < row_index {lo = min(lo, i)}
				if i > row_index {hi = max(hi, i)}
			}
		}

		if lo == max(int) && hi == -1 {
			for &r in rows[0:row_index+1] {r.selected = true}
		} else if hi == -1 {
			for &r in rows[lo:row_index+1] {r.selected = true}
		} else if lo == max(int) {
			for &r in rows[row_index+1:hi] {r.selected = true}
		} else if ((hi-row_index) < (row_index-lo)) {
			for &r in rows[row_index:hi+1] {r.selected = true}
		} else {
			for &r in rows[lo:row_index+1] {r.selected = true}
		}
	}
	else if ctrl {
		row.selected = true
	}
}

table_show :: proc(
	str_id: cstring, display_info: Table_Display_Info,
	scrolling_text_timer: f64
) -> (result: Table_Result, shown: bool) {
	header_context_menu :: proc(t: ^Table_State, columns: []Table_Column_Info) {
		if imgui.MenuItem("Show all columns") {
			for &col in t.columns[:t.column_count] do col.hidden = false
			t.need_distribute_weights = true
		}

		imgui.Separator()

		for col_info, i in columns {
			col := &t.columns[i]
			shown := !col.hidden
			if imgui.MenuItemBoolPtr(col_info.name, nil, &shown) {
				col.hidden = !shown
				t.need_distribute_weights = true
			}
		}
	}

	columns: []Table_Column_Info
	row_count: int
	table_size: [2]f32
	table_pos: [2]f32
	padding: [2]f32
	style: ^imgui.Style

	columns = display_info.columns
	row_count = len(columns[0].rows)
	assert(len(display_info.rows) == row_count)
	table_pos = imgui.GetCursorScreenPos()
	table_size = imgui.GetContentRegionAvail()
	style = imgui.GetStyle()
	padding = style.CellPadding
	
	table_size.x -= style.ScrollbarSize
	if table_size.x <= (padding.x*2) do return

	t, already_exists := ctx_add_or_get_table(imgui.GetID(str_id))

	if !already_exists || t.column_count != len(columns) do _table_init(t, columns)

	if t.need_distribute_weights do _table_distribute_weights(t)
	t.need_distribute_weights = false

	drawlist := imgui.GetWindowDrawList()
	row_height := imgui.GetTextLineHeight() + (padding.y * 2)
	cursor := imgui.GetCursorScreenPos()

	// -------------------------------------------------------------------------
	// Headers
	// -------------------------------------------------------------------------
	{
		offset: f32

		imgui.PushStyleVarImVec2(.ItemSpacing, {0, 0})
		defer imgui.PopStyleVar()

		imgui.DrawList_AddRectFilled(drawlist,
			cursor, cursor + {table_size.x, row_height},
			imgui.GetColorU32(.TableHeaderBg)
		)

		for col_index in t.column_order[:len(columns)] {
			col_width: f32
			col_state: ^Table_Column
			col: Table_Column_Info
			bg_rect_min, bg_rect_max: [2]f32

			col_state = &t.columns[col_index]
			
			if col_state.hidden do continue
			
			col = columns[col_index]
			col_width = table_size.x * t.columns[col_index].weight

			if col_width <= (padding.x*2) do continue

			bg_rect_min = {cursor.x + offset, cursor.y}
			bg_rect_max = bg_rect_min + {col_width, row_height}
			
			if imgui.InvisibleButton(col.name, {col_width, row_height}) {
				switch col_state.sort_order {
					case .None: col_state.sort_order = .Ascending
					case .Ascending: col_state.sort_order = .Descending
					case .Descending: col_state.sort_order = .None
				}

				if col_state.sort_order != .None do result.sort_by_column = col_index
				result.sort_order = col_state.sort_order
			}
			imgui.SameLine()

			if imgui.BeginPopupContextItem() {
				header_context_menu(t, columns)
				imgui.EndPopup()
			}

			if imgui.IsItemHovered() do imgui.DrawList_AddRectFilled(
				drawlist, bg_rect_min, bg_rect_max, imgui.GetColorU32(.HeaderHovered)
			)

			imgui.DrawList_AddText(drawlist,
				{cursor.x + offset, cursor.y} + padding,
				imgui.GetColorU32(.Text), col.name,
			)

			offset += col_width
		}

		imgui.NewLine()
	}
	
	imgui.BeginChild(str_id, imgui.GetContentRegionAvail()) or_return
	defer imgui.EndChild()
	cursor = imgui.GetCursorScreenPos()	
	scroll_y := imgui.GetScrollY()

	// -------------------------------------------------------------------------
	// Row clipping
	// -------------------------------------------------------------------------
	display_start := int(scroll_y / row_height)
	display_end := int((scroll_y + table_size.y) / row_height) + 1
	display_start = max(display_start, 0)
	display_end = min(display_end, row_count)
	
	// -------------------------------------------------------------------------
	// Row text
	// -------------------------------------------------------------------------
	{
		offset: f32

		for col_index in t.column_order[:len(columns)] {
			col := columns[col_index]

			if t.columns[col_index].hidden do continue

			width := table_size.x * t.columns[col_index].weight

			if width <= (padding.x*2) do continue
			
			imgui.PushClipRect(
				{cursor.x + offset + padding.x, cursor.y + scroll_y},
				{cursor.x + offset + width - padding.x, cursor.y + table_size.y + scroll_y},
				true
			)
			defer imgui.PopClipRect()

			for row, i in col.rows[display_start:display_end] {
				draw_scrolling_text(
					{
						cursor.x + offset,
						cursor.y + (f32(i + display_start) * row_height),
					} + padding,
					row.text, scrolling_text_timer, width, row.text_width
				)
			}
			
			offset += width
		}
	}


	// -------------------------------------------------------------------------
	// Vertical borders
	// -------------------------------------------------------------------------
	if len(columns) > 1 {
		offset: f32
		accum_weight: f32
		relative_mouse_pos: f32

		resize_right_accum_weight: f32
		resize_left_accum_weight: f32
		resize_left_col: ^Table_Column
		resize_right_col: ^Table_Column

		length := table_size.y

		get_next_visible_column :: proc(
			t: ^Table_State, display_index: int
		) -> (col: ^Table_Column, right_weight: f32) {
			index_in_order := -1

			for col_index, i in t.column_order[display_index+1:t.column_count] {
				if !t.columns[col_index].hidden {
					index_in_order = i + display_index + 1
					col = &t.columns[col_index]
					break
				}
			}

			if index_in_order == -1 do return

			for col_index in t.column_order[index_in_order+1:t.column_count] {
				if !t.columns[col_index].hidden {
					right_weight += t.columns[col_index].weight
				}
			}

			return
		}

		relative_mouse_pos = (imgui.GetMousePos().x - table_pos.x) / table_size.x
		
		for col_index, col_display_index in t.column_order[0:len(columns)-1] {
			next_col: ^Table_Column
			weight_to_right_of_next_col: f32
			col: ^Table_Column
			width: f32
			pos: [2]f32
			border_color: u32
			
			col = &t.columns[col_index]

			if col.hidden do continue
			
			width = table_size.x * col.weight
			offset += width
			pos = cursor + {offset, scroll_y}
			
			next_col, weight_to_right_of_next_col = get_next_visible_column(t, col_display_index)
			
			if next_col == nil do continue

			button_min := [2]f32{pos.x - 3, pos.y}
			button_max := [2]f32{pos.x + 3, pos.y + table_size.y}
			border_color = imgui.GetColorU32(.TableBorderStrong)

			// Resizing
			{
				hovered, held: bool
				color: u32 = 0xff0000ff
				id := imgui.GetIDInt(auto_cast col_index)
				
				imgui.ItemAdd({button_min, button_max}, id)
				imgui.ButtonBehavior({button_min, button_max}, id, &hovered, &held, {.MouseButtonLeft})

				if hovered || held do imgui.SetMouseCursor(.ResizeEW)
				
				if hovered do border_color = imgui.GetColorU32(.ResizeGripHovered)

				if held {
					resize_left_accum_weight = accum_weight
					resize_right_accum_weight = weight_to_right_of_next_col
					resize_left_col = col
					resize_right_col = next_col
					border_color = imgui.GetColorU32(.ResizeGripActive)
				}
				
				if hovered do color = max(u32)
				if held do color = 0xff00ff00
			}

			imgui.DrawList_AddLine(drawlist, pos, pos + {0, length}, border_color)
			accum_weight += col.weight
		}

		if resize_left_col != nil && resize_right_col != nil {
			resize_left_col.weight = relative_mouse_pos - resize_left_accum_weight
			resize_right_col.weight = (1 - resize_right_accum_weight) - relative_mouse_pos
		}
	}

	// -------------------------------------------------------------------------
	// Row backgrounds and behaviour
	// -------------------------------------------------------------------------
	{
		imgui.PushStyleVarImVec2(.ItemSpacing, {0, 0})
		defer imgui.PopStyleVar()

		// Add empty space for scrolling
		if display_start > 0 do imgui.Dummy({table_size.x, f32(display_start) * row_height})

		imgui.DrawList_PushClipRect(
			drawlist,
			{cursor.x, cursor.y + scroll_y},
			{cursor.x + table_size.x, cursor.y + table_size.y + scroll_y},
			true
		)
		defer imgui.DrawList_PopClipRect(drawlist)

		for row_index in display_start..<display_end {
			clicked: bool
			keep_selection: bool
			select: bool

			row := &display_info.rows[row_index]

			y := f32(row_index) * row_height
			bg_rect_min := [2]f32{cursor.x, cursor.y + y}
			bg_rect_max := [2]f32{cursor.x + table_size.x, cursor.y + y + row_height}

			if row_index % 2 == 0 {
				imgui.DrawList_AddRectFilled(
					drawlist,
					bg_rect_min,
					bg_rect_max,
					imgui.GetColorU32(.TableRowBgAlt),
				)
			}

			if row.id == display_info.highlight_row_id {
				imgui.DrawList_AddRectFilled(
					drawlist,
					bg_rect_min,
					bg_rect_max,
					display_info.highlight_color,
				)
			}

			imgui.PushIDInt(auto_cast row_index)
			defer imgui.PopID()

			clicked |= imgui.InvisibleButton("##button", {table_size.x, row_height})

			if row.selected {
				imgui.DrawList_AddRectFilled(
					drawlist,
					bg_rect_min,
					bg_rect_max,
					imgui.GetColorU32(.Header),
				)
			}

			if imgui.IsItemHovered() {
				imgui.DrawList_AddRectFilled(
					drawlist,
					bg_rect_min,
					bg_rect_max,
					imgui.GetColorU32(.HeaderHovered),
				)
			}

			if imgui.IsItemClicked(.Right) {
				imgui.OpenPopupID(display_info.context_menu_id)
				select = true
				keep_selection = true
			}

			if clicked {
				result.left_clicked_row = row.id
				select = true
			}

			if imgui.IsItemClicked(.Middle) {
				result.middle_clicked_row = row.id
				select = true
			}

			if select do _table_selection_logic(display_info.rows, row_index, keep_selection)
		}

		// Horizontal borders
		for row_index in display_start..<display_end {
			y := f32(row_index) * row_height
			bg_rect_min := [2]f32{cursor.x, cursor.y + y}
			bg_rect_max := [2]f32{cursor.x + table_size.x, cursor.y + y + row_height}
			imgui.DrawList_AddLine(drawlist, 
				{cursor.x, cursor.y + y}, 
				{cursor.x + table_size.x, cursor.y + y},
				imgui.GetColorU32(.TableBorderStrong)
			)
		}

		// Add empty space for scrolling
		if (row_count - display_end) > 0 {
			imgui.Dummy({table_size.x, f32(row_count - display_end) * row_height})
		}
	}


	shown = true
	return
}

table_test :: proc(uptime: f64) -> bool {	
	defer imgui.End()
	imgui.Begin("Table Test") or_return

	columns := []Table_Column_Info {
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

	table_show("Test Table", Table_Display_Info {
		columns = columns,
		rows = {{id = 1}, {id = 2}, {id = 3}},
		highlight_color = 0xdd00ffdd,
		highlight_row_id = 2,
	}, uptime)

	return true
}
