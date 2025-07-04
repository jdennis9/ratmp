#+private
package sys_main

import "core:log"
import win "core:sys/windows"

import imgui_win32 "src:thirdparty/odin-imgui/imgui_impl_win32"

import "src:build"
import "src:sys"
import "src:util"

DWMA_USE_IMMERSIVE_DARK_MODE :: 20
TRAY_BUTTON_SHOW :: 1
TRAY_BUTTON_EXIT :: 2

_add_tray_icon :: proc() {
	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = _win32.hwnd,
		uID = 1,
		uFlags = win.NIF_TIP|win.NIF_MESSAGE|win.NIF_ICON,
		uCallbackMessage = win.WM_APP + 1,
		uVersion = 4,
		hIcon = _win32.icon,
	}

	tip :: build.PROGRAM_NAME
	copy(data.szTip[:], win.L(tip)[:len(tip)])

	win.Shell_NotifyIconW(win.NIM_ADD, &data)

	_win32.tray_popup = win.CreatePopupMenu()
	if _win32.tray_popup != nil {
		win.AppendMenuW(_win32.tray_popup, win.MF_STRING, TRAY_BUTTON_SHOW, win.L("Show"))
		win.AppendMenuW(_win32.tray_popup, win.MF_STRING, TRAY_BUTTON_EXIT, win.L("Exit"))
	}
}

_remove_tray_icon :: proc() {
	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = _win32.hwnd,
		uID = 1,
	}

	win.Shell_NotifyIconW(win.NIM_DELETE, &data)

	if _win32.tray_popup != nil {
		win.DestroyMenu(_win32.tray_popup)
	}
}

_win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> int {
	context = _win32.ctx

	if (imgui_win32.WndProcHandler(hwnd, msg, wparam, lparam) != 0) {
		return 1
	}

	switch msg {
		case win.WM_SIZE: {
			_win32.resize_width = int(win.LOWORD(lparam))
			_win32.resize_height = int(win.HIWORD(lparam))
		}
		case win.WM_QUIT: {
			log.info("Received quit message")
			_win32.running = false
		}
		case win.WM_CLOSE: {
			switch _win32.cl.settings.close_policy {
				case .AlwaysAsk:
					text := "Keep running in the background? The default behaviour for this can be changed in your settings"
					if sys.open_dialog("Minimize to tray?", .YesNo, text) {
						win.ShowWindow(hwnd, win.SW_HIDE)
					}
					else {
						win.PostQuitMessage(0)
					}
				case .MinimizeToTray:
					win.ShowWindow(hwnd, win.SW_HIDE)
				case .Exit:
					win.PostQuitMessage(0)
			}
			return 0
		}
		case win.WM_DPICHANGED: {
			_win32.dpi_scale = imgui_win32.GetDpiScaleForHwnd(_win32.hwnd)
			//set_ui_scale(_win32.dpi_scale)
			return 0
		}
		case win.WM_APP+1: {
			if win.LOWORD(lparam) == win.WM_LBUTTONDOWN {
				win.ShowWindow(_win32.hwnd, win.SW_SHOWDEFAULT)
			}
			else if (win.LOWORD(lparam) == win.WM_RBUTTONDOWN) {
				mouse: win.POINT
				win.GetCursorPos(&mouse)
				win.TrackPopupMenu(_win32.tray_popup, win.TPM_LEFTBUTTON, mouse.x, mouse.y, 0, _win32.hwnd, nil)
				win.PostMessageW(_win32.hwnd, win.WM_NULL, 0, 0)
			}
			return 0
		}
		case win.WM_COMMAND: {
			switch wparam {
			case TRAY_BUTTON_SHOW: win.ShowWindow(_win32.hwnd, win.SW_SHOWDEFAULT)
			case TRAY_BUTTON_EXIT: _win32.running = false
			}
			return 0
		}

	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

_drag_drop_drop :: proc "c" (path: cstring) {
	context = _win32.ctx
	if _win32.drag_drop_done {return}
	else if path == nil {
		_win32.drag_drop_done = true
	}
	else {
		buf: sys.Path
		util.copy_string_to_buf(buf[:], string(path))
		append(&_win32.drag_drop_payload, buf)
		log.debug(path)
	}
}

