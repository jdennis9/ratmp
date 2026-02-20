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
	Custom implemenation of tables that makes some assumptions that simplifies
	the logic and helps a bit with CPU usage. Assumes that rows only contain one line of text
	and that the number of rows in always known ahead of time.
*/


import imgui "src:thirdparty/odin-imgui"

TABLE_MAX_COLUMNS :: 16
TABLE_MAX_COLUMN_NAME_LEN :: 24

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
	sort_by_column: int,
	context_menu_target: Maybe(Table_Row_ID),
}

Table_Result :: struct {
	left_clicked_row: Maybe(Table_Row_ID),
	middle_clicked_row: Maybe(Table_Row_ID),
	sort_by_column: Maybe(int),
	sort_order: Table_Sort_Order,
	context_menu_opened_with: Maybe(Table_Row_ID),
	selection_changed: bool,
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
_table_init :: proc(str_id: cstring, t: ^Table_State, columns: []Table_Column_Info) {
	t.column_count = len(columns)
	t.sort_by_column = -1

	log.debug("Init table", str_id)

	if t.settings_loaded {
		// Validate weights
		total_weight: f32
		have_visible_column: bool

		for &col in t.columns[:t.column_count] {
			if col.hidden do continue
			total_weight += col.weight
			have_visible_column = true
		}

		if total_weight <= 0.99 || total_weight >= 1.01 do _table_distribute_weights(t)

		t.settings_loaded = false
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
	drag_drop_payload_type: cstring,
}

@(private="file")
_table_selection_logic :: proc(table: ^Table_State, rows: []Table_Row, row_index: int, keep_selection: bool) {
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
	str_id: cstring, display_info: Table_Display_Info
) -> (result: Table_Result, shown: bool) {

	RESIZE_GRAB_THICKNESS :: 3

	show_vertical_borders :: proc(
		t: ^Table_State, cursor: [2]f32, table_pos: [2]f32, table_size: [2]f32, y_offset: f32, height: f32
	) {
		offset: f32
		accum_weight: f32
		relative_mouse_pos: f32

		resize_right_accum_weight: f32
		resize_left_accum_weight: f32
		resize_left_col: ^Table_Column
		resize_right_col: ^Table_Column
		scroll_y := imgui.GetScrollY()
		drawlist := imgui.GetWindowDrawList()

		length := height

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
		
		for col_index, col_display_index in t.column_order[0:t.column_count] {
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

			button_min := [2]f32{pos.x - RESIZE_GRAB_THICKNESS, pos.y}
			button_max := [2]f32{pos.x + RESIZE_GRAB_THICKNESS, pos.y + length}
			border_color = imgui.GetColorU32(.TableBorderStrong)

			// Resizing
			{
				hovered, held: bool
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
			}

			imgui.DrawList_AddLine(drawlist, pos, pos + {0, length}, border_color)
			accum_weight += col.weight
		}

		if resize_left_col != nil && resize_right_col != nil {
			min_weight :: 0.02
			new_left_weight := relative_mouse_pos - resize_left_accum_weight
			new_right_weight := (1 - resize_right_accum_weight) - relative_mouse_pos

			// Size correction
			if new_left_weight <= min_weight {
				diff := min_weight - new_left_weight
				new_right_weight -= diff
				new_left_weight += diff
			}
			else if new_right_weight <= min_weight {
				diff := min_weight - new_right_weight
				new_right_weight += diff
				new_left_weight -= diff
			}

			resize_left_col.weight = new_left_weight
			resize_right_col.weight = new_right_weight
		}
	}

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
	table_focused: bool

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

	if !already_exists || t.column_count != len(columns) || t.settings_loaded do _table_init(str_id, t, columns)

	if t.need_distribute_weights do _table_distribute_weights(t)
	t.need_distribute_weights = false

	drawlist := imgui.GetWindowDrawList()
	row_height := imgui.GetTextLineHeight() + (padding.y * 2)
	cursor := imgui.GetCursorScreenPos()

	show_vertical_borders(t, cursor, table_pos, table_size, 0, row_height)

	// -------------------------------------------------------------------------
	// Headers
	// -------------------------------------------------------------------------
	{
		offset: f32

		imgui.PushStyleVarImVec2(.ItemSpacing, {RESIZE_GRAB_THICKNESS, 0})
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

			imgui.PushClipRect(bg_rect_min, bg_rect_max, true)
			defer imgui.PopClipRect()
			
			if imgui.InvisibleButton(col.name, {col_width - RESIZE_GRAB_THICKNESS, row_height}) {
				switch col_state.sort_order {
					case .None: col_state.sort_order = .Ascending
					case .Ascending: col_state.sort_order = .Descending
					case .Descending: col_state.sort_order = .None
				}

				if col_state.sort_order != .None do result.sort_by_column = col_index
				result.sort_order = col_state.sort_order
				t.sort_by_column = col_index
			}
			imgui.SameLine()

			// -----------------------------------------------------------------
			// Sort order triangle
			// -----------------------------------------------------------------
			if col_state.sort_order != .None && t.sort_by_column == col_index {
				triangle_padding := style.FramePadding

				triangle_size := (row_height - (triangle_padding.x * 2)) * 0.25
				triangle_size = clamp(triangle_size, 1, 30)

				triangle_pos := [2]f32{
					bg_rect_max.x - triangle_padding.x - 6,
					bg_rect_min.y + triangle_padding.y + (row_height * 0.5) - triangle_size
				}

				if col_state.sort_order == .Ascending {
					imgui.DrawList_AddTriangleFilled(
						drawlist,
						triangle_pos + {0, -triangle_size},
						triangle_pos + {triangle_size, triangle_size},
						triangle_pos + {-triangle_size, triangle_size},
						imgui.GetColorU32(.Text)
					)
				}
				else if col_state.sort_order == .Descending {
					imgui.DrawList_AddTriangleFilled(
						drawlist,
						triangle_pos + {0, triangle_size},
						triangle_pos + {-triangle_size, -triangle_size},
						triangle_pos + {triangle_size, -triangle_size},
						imgui.GetColorU32(.Text)
					)
				}
			}

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
	
	defer imgui.EndChild()
	imgui.BeginChild(str_id, imgui.GetContentRegionAvail()) or_return

	
	table_focused = imgui.IsWindowFocused()
	
	// -------------------------------------------------------------------------
	// Jumping
	// -------------------------------------------------------------------------
	if display_info.highlight_row_id != 0 && table_focused && is_key_chord_pressed(.ImGuiMod_Ctrl, .Space) {
		jump_row_id := display_info.highlight_row_id
		
		for row, index in display_info.rows {
			if row.id == jump_row_id {
				imgui.SetScrollY(f32(index) * row_height - (table_size.y * 0.5))
				break
			}
		}
	}

	// -------------------------------------------------------------------------
	// Select all
	// -------------------------------------------------------------------------
	if table_focused && is_key_chord_pressed(.ImGuiMod_Ctrl, .A) {
		for &row in display_info.rows do row.selected = true
	}
	
	cursor = imgui.GetCursorScreenPos()	
	scroll_y := imgui.GetScrollY()
	
	show_vertical_borders(t, cursor, table_pos, table_size, 0, table_size.y)

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
	if display_start <= display_end {
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
					row.text, width, row.text_width
				)
			}
			
			offset += width
		}
	}


	// -------------------------------------------------------------------------
	// Row backgrounds and behaviour
	// -------------------------------------------------------------------------
	{
		if !imgui.IsPopupOpenID(display_info.context_menu_id, {}) do t.context_menu_target = nil
		else do result.context_menu_opened_with = t.context_menu_target

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

			// -----------------------------------------------------------------
			// Drag-drop
			// -----------------------------------------------------------------
			if imgui.BeginDragDropSource() {
				selected_rows: [dynamic]Table_Row_ID
				defer delete(selected_rows)

				for row in display_info.rows {
					if row.selected do append(&selected_rows, row.id)
				}

				imgui.SetDragDropPayload(display_info.drag_drop_payload_type,
					raw_data(selected_rows), auto_cast(size_of(Table_Row_ID) * len(selected_rows))
				)
				imgui.EndDragDropSource()
			}

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
				t.context_menu_target = row.id
				result.context_menu_opened_with = row.id
			}

			if clicked {
				result.left_clicked_row = row.id
				select = true
			}

			if imgui.IsItemClicked(.Middle) {
				result.middle_clicked_row = row.id
				select = true
			}

			if select {
				_table_selection_logic(t, display_info.rows, row_index, keep_selection)
				result.selection_changed = true
			}
		}

		// Horizontal borders
		for row_index in display_start..<display_end {
			y := f32(row_index) * row_height
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

	//result.selection_serial = t.selection_serial
	shown = true
	return
}
