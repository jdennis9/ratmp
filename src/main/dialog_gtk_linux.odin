package main

import lm "src:bindings/linux_misc"

dialog_init_gtk :: proc() {
	_dialog_impl_show_message_box = proc(
		type: Message_Box_Type, urgency: Message_Box_Urgency, title, body: cstring
	) -> (res: Message_Box_Response, error: Error) {
		ext_type := [Message_Box_Type]lm.Message_Type {
			.Message = .Message,
			.OkCancel = .OkCancel,
			.YesNo = .YesNo,
		}

		ext_urgency := [Message_Box_Urgency]lm.Urgency {
			.Info = .Info,
			.Question = .Question,
			.Warning = .Warning,
			.Error = .Error,
		}

		ext_res := lm.message_box(body, ext_type[type], ext_urgency[urgency])

		switch ext_res {
		case .OkYes: res = .OkYes
		case .No: res = .No
		case .Cancel: res = .Cancel
		}

		return
	}
}

