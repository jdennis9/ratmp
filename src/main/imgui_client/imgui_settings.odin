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
package client

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:reflect"
import "base:runtime"
import "core:mem"
import imgui "src:thirdparty/odin-imgui"

_settings_ctx: runtime.Context

@private
register_imgui_settings_handler :: proc() {
	_settings_ctx = context

	_open :: proc "c" (
		ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, name_cstring: cstring
	) -> rawptr {
		name := string(name_cstring)
		for info, id in UI_WINDOWS {
			if info.internal_name == name {
				return cast(rawptr) (uintptr(id) + 1)
			}
		}

		return nil
	}

	_read_line :: proc "c" (
		ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, entry: rawptr, line: cstring
	) {
		context         = _settings_ctx
		window_id      := cast(UI_Window_ID) (uintptr(entry) -1)
		temp_allocator := get_frame_allocator()

		frame_allocator_guard()

		if !reflect.enum_value_has_name(window_id) do return

		tokens := strings.split_n(string(line), "=", 2, temp_allocator)
		if len(tokens) < 2 do return

		info := UI_WINDOWS[window_id]

		switch tokens[0] {
		case "_Open":
			set_window_open(window_id, strconv.parse_bool(tokens[1]) or_else is_window_open(window_id))
			return
		case:
			info.procedure({
				type       = .LoadState,
				load_state = {
					key   = tokens[0],
					value = tokens[1]
				}
			})
		}
	}

	_write :: proc "c" (
		ctx: ^imgui.Context, handler: ^imgui.SettingsHandler, out_buf: ^imgui.TextBuffer
	) {
		context = _settings_ctx

		m: map[string]string
		defer delete(m)

		frame_allocator_guard()
		temp_allocator := get_frame_allocator()

		for info, window_id in UI_WINDOWS {
			clear(&m)

			info.procedure({
				type       = .SaveState,
				save_state = {
					m         = &m,
					allocator = get_frame_allocator()
				},
			})

			imgui.TextBuffer_append(
				out_buf, fmt.caprintf("[RATMP][%s]\n", info.internal_name, allocator=temp_allocator)
			)

			imgui.TextBuffer_append(out_buf,
				fmt.caprintf("_Open=%t\n", is_window_open(window_id), allocator=temp_allocator)
			)

			for k, v in m {
				imgui.TextBuffer_append(
					out_buf, fmt.caprintf("%s=%s\n", k, v, allocator=temp_allocator)
				)
			}
		}
	}

	s := imgui.SettingsHandler {
		ReadOpenFn = _open,
		ReadLineFn = _read_line,
		WriteAllFn = _write,
		TypeHash   = imgui.cImHashStr("RATMP"),
		TypeName   = "RATMP",
	}

	imgui.AddSettingsHandler(&s)
}

