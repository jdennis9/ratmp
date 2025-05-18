#+private
package client

import "core:thread"
import "core:strings"

_Dialog_Type :: enum {
	Message,
	YesNo,
	OkCancel,
}

_Dialog_State :: struct {
	thread: ^thread.Thread,
	type: _Dialog_Type,
	title: string,
	message: string,
	result: bool,
}

@private
_async_dialog_proc :: proc(dialog_thread: ^thread.Thread) {
	state := cast(^_Dialog_State) dialog_thread.data
	state.result = _open_dialog(state.title, state.type, state.message)
}

_async_dialog_open :: proc(state: ^_Dialog_State, type: _Dialog_Type, title, message: string, allocator := context.allocator) {
	if state.thread != nil && !thread.is_done(state.thread) {
		return
	}

	if state.thread != nil {
		thread.join(state.thread)
		_async_dialog_destroy(state)
	}

	state.type = type
	state.result = false
	state.message = strings.clone(message, allocator)
	state.title = strings.clone(title, allocator)
	state.thread = thread.create(_async_dialog_proc)
	state.thread.data = state

	thread.start(state.thread)
}

_async_dialog_destroy :: proc(state: ^_Dialog_State) {
	if state.thread == nil {return}
	thread.join(state.thread)
	thread.destroy(state.thread)
	state.thread = nil
	delete(state.message)
	delete(state.title)
	state.message = ""
	state.title = ""
}

_async_dialog_get_result :: proc(state: ^_Dialog_State) -> (result: bool, have_result: bool) {
	if state.thread == nil || !thread.is_done(state.thread) {
		return
	}

	result = state.result
	have_result = true

	_async_dialog_destroy(state)

	return
}
