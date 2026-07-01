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

