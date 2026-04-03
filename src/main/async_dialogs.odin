#+private file
package main

import "core:mem"
import sa "core:container/small_array"
import "core:sync"
import "core:fmt"
import "core:thread"
import hm "core:container/handle_map"

Message_Box_Handle :: UID

_Message_Thread :: struct {
	message: [1024]u8,
	title: [128]u8,
	type: Message_Box_Type,
	urgency: Message_Box_Urgency,
	runner: ^thread.Thread,
	id: UID,
}

_Message_Response :: struct {
	id: UID,
	res: Message_Box_Response,
}

_open_messages: [20]_Message_Thread
_response_lock: sync.Mutex
_responses: sa.Small_Array(20, _Message_Response)

_message_box_thread :: proc(t: ^thread.Thread) {
	state := cast(^_Message_Thread) t.data

	response, error := _dialog_impl_show_message_box(
		state.type,
		state.urgency,
		cstring(&state.title[0]),
		cstring(&state.message[0]),
	)

	if state.type != .Message {
		sync.lock(&_response_lock)
		sa.append(&_responses, _Message_Response {
			id = state.id,
			res = response,
		})
		sync.unlock(&_response_lock)
	}
}

@private
show_message_box_async :: proc(type: Message_Box_Type, urgency: Message_Box_Urgency,
	title: cstring, body_args: ..any, sep := " "
) -> (h: Message_Box_Handle, error: Error) {
	if _dialog_impl_show_message_box == nil do return 0, Custom_Error.NotImplemented

	index := -1
	for &m, i in _open_messages {
		if m.runner == nil {
			index = i
			break
		}
	}

	if index == -1 do return 0, mem.Allocator_Error.Out_Of_Memory

	mt := &_open_messages[index]

	for &r in mt.message do r = 0
	for &r in mt.title do r = 0

	fmt.bprint(mt.message[:len(mt.message)-1], ..body_args, sep=sep)
	copy(mt.title[:len(mt.title)-1], string(title))

	mt.id = generate_uid()
	mt.type = type
	mt.urgency = urgency
	mt.runner = thread.create(_message_box_thread)
	mt.runner.data = mt
	mt.runner.init_context = context
	thread.start(mt.runner)

	return
}

@private @require_results
message_box_get_response :: proc(
	h: Message_Box_Handle
) -> (res: Message_Box_Response, have_response: bool) {
	if h == 0 do return

	sync.lock(&_response_lock)
	defer sync.unlock(&_response_lock)

	for r, i in _responses.data[:_responses.len] {
		if r.id == h {
			sa.unordered_remove(&_responses, i)
			return r.res, true
		}
	}

	return
}


@private
update_async_dialogs :: proc() {
	for &d in _open_messages {
		if d.runner == nil || !thread.is_done(d.runner) do continue
		thread.destroy(d.runner)
		d.runner = nil
		d.id = 0
	}
}

