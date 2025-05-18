package client

import win "core:sys/windows"
import "core:unicode/utf16"

_open_dialog :: proc(title: string, type: _Dialog_Type, message: string) -> bool {
	message_u16: [512]u16
	title_u16: [64]u16

	utf16.encode_string(message_u16[:511], message)
	utf16.encode_string(title_u16[:63], title)

	switch type {
		case .Message: {
			win.MessageBoxW(nil, raw_data(message_u16[:]), raw_data(title_u16[:]), win.MB_ICONWARNING)
			return true
		}
		case .YesNo: {
			return win.MessageBoxW(nil, raw_data(message_u16[:]), raw_data(title_u16[:]), 
				win.MB_ICONQUESTION|win.MB_YESNO) == win.IDYES
		}
		case .OkCancel: {
			return win.MessageBoxW(nil, raw_data(message_u16[:]), raw_data(title_u16[:]), 
				win.MB_ICONQUESTION|win.MB_OKCANCEL) == win.IDOK
		}
	}

	return true
}

