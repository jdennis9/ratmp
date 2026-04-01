package main

import win "core:sys/windows"

dialog_init_windows :: proc() {
	_dialog_impl_show_message_box = proc(
		type: Message_Box_Type, urgency: Message_Box_Urgency, title, body: cstring
	) -> (res: Message_Box_Response, error: Error) {
		message_u16 := cstring16(raw_data(win.utf8_to_utf16_alloc(string(body), context.allocator)))
		defer delete(message_u16)
		title_u16 := cstring16(raw_data(win.utf8_to_utf16_alloc(string(title), context.allocator)))
		defer delete(title_u16)

		icon: win.UINT
		switch urgency {
		case .Info: icon = win.MB_ICONINFORMATION
		case .Question: icon = win.MB_ICONQUESTION
		case .Warning: icon = win.MB_ICONWARNING
		case .Error: icon = win.MB_ICONERROR
		}

		switch type {
		case .Message:
			win.MessageBoxW(nil, message_u16, title_u16, icon)
			return
		case .OkCancel:
			r := win.MessageBoxW(nil, message_u16, title_u16, icon | win.MB_OKCANCEL)
			switch r {
			case win.IDOK: res = .OkYes
			case win.IDCANCEL: res = .Cancel
			}
			return
		case .YesNo:
			r := win.MessageBoxW(nil, message_u16, title_u16, icon | win.MB_YESNO)
			switch r {
			case win.IDYES: res = .OkYes
			case win.IDNO: res = .No
			}
			return
		}


		return
	}
}
