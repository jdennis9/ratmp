package server

Current_Track_Changed_Event :: struct {
	track_id: Track_ID,
}

State_Changed_Event :: struct {
	paused: bool,
}

Event :: union {
	Current_Track_Changed_Event,
	State_Changed_Event,
}

Event_Handler_Proc :: #type proc(state: Server, data: rawptr, event: Event)

Event_Handler :: struct {
	handler_proc: Event_Handler_Proc,
	data: rawptr,
}

add_event_handler :: proc(state: ^Server, handler: Event_Handler_Proc, data: rawptr) {
	append(&state.event_handlers, Event_Handler{
		handler_proc = handler,
		data = data,
	})
}

send_event :: proc(state: ^Server, event: Event) {
	if state.wake_proc != nil {state.wake_proc()}
	append(&state.event_queue, event)
}

handle_events :: proc(state: ^Server) {
	for handler in state.event_handlers {
		for event in state.event_queue {
			handler.handler_proc(state^, handler.data, event)
		}
	}
	clear(&state.event_queue)
	free_all(context.temp_allocator)

	flush_scan_queue(state)
	library_save_dirty_playlists(state.library)
	_background_scan_output_results(&state.library, &state.background_scan)

	if state.library.serial != state.library_save_serial {
		state.library_save_serial = state.library.serial
		library_save_to_file(state.library, state.paths.library)
	}
}
