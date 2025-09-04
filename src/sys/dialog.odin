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
package sys

import "core:thread"
import "core:strings"

import "src:sys"

Dialog_Type :: enum {
	Message,
	YesNo,
	OkCancel,
}

Dialog_State :: struct {
	thread: ^thread.Thread,
	type: Dialog_Type,
	title: string,
	message: string,
	result: bool,
}

@private
_async_dialog_proc :: proc(dialog_thread: ^thread.Thread) {
	state := cast(^Dialog_State) dialog_thread.data
	state.result = sys.open_dialog(state.title, state.type, state.message)
}

async_dialog_open :: proc(state: ^Dialog_State, type: Dialog_Type, title, message: string, allocator := context.allocator) {
	if state.thread != nil && !thread.is_done(state.thread) {
		return
	}

	if state.thread != nil {
		thread.join(state.thread)
		async_dialog_destroy(state)
	}

	state.type = type
	state.result = false
	state.message = strings.clone(message, allocator)
	state.title = strings.clone(title, allocator)
	state.thread = thread.create(_async_dialog_proc)
	state.thread.data = state

	thread.start(state.thread)
}

async_dialog_destroy :: proc(state: ^Dialog_State) {
	if state.thread == nil {return}
	thread.join(state.thread)
	thread.destroy(state.thread)
	state.thread = nil
	delete(state.message)
	delete(state.title)
	state.message = ""
	state.title = ""
}

async_dialog_get_result :: proc(state: ^Dialog_State) -> (result: bool, have_result: bool) {
	if state.thread == nil || !thread.is_done(state.thread) {
		return
	}

	result = state.result
	have_result = true

	async_dialog_destroy(state)

	return
}
