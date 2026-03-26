#+private file
package main

import "base:runtime"
import lm "src:bindings/linux_misc"

_systray_appindicator: struct {
	callback: Sys_Tray_Proc,
	callback_data: rawptr,
	ctx: runtime.Context,
}

_callback_wrapper :: proc "c" (in_event: lm.Systray_Event) {
	context = _systray_appindicator.ctx
	button: Sys_Tray_Button
	switch in_event {
		case .Show: button = .Show
		case .Exit: button = .Exit
	}

	_systray_appindicator.callback(_systray_appindicator.callback_data, button)
}

@private
systray_use_linux_appindicator :: proc() {
	_systray_impl_create = proc(cb: Sys_Tray_Proc, cbd: rawptr) -> bool {
		_systray_appindicator.callback = cb
		_systray_appindicator.callback_data = cbd
		_systray_appindicator.ctx = context
		lm.systray_init(_callback_wrapper)
		return true
	}

	_systray_impl_destroy = proc() {
	}
}
