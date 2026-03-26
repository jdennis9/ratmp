#+private file
package main

import win "core:sys/windows"
import imgui_win32 "src:thirdparty/odin-imgui/imgui_impl_win32"

WINDOW_CLASS_NAME :: PROGRAM_ID + "_window_class"
TRAY_BUTTON_SHOW :: 0
TRAY_BUTTON_EXIT :: 1

_win: struct {
	hinstance: win.HINSTANCE,
	hwnd: win.HWND,
	events: Platform_Events,
	tray_callback: Sys_Tray_Proc,
	tray_callback_data: rawptr,
	icon: win.HICON,
	tray_menu: win.HMENU,
}

@private
platform_init_win32 :: proc(tray_cb: Sys_Tray_Proc, tray_cbd: rawptr) -> bool {
	_platform_impl_shutdown = proc() {
		win.UnregisterClassW(WINDOW_CLASS_NAME, _win.hinstance)
	}

	_platform_impl_make_window = proc() -> bool {
		// -----------------------------------------------------------------------
		// Window & DX11
		// -----------------------------------------------------------------------
		_win.hwnd = win.CreateWindowExW(
			0, WINDOW_CLASS_NAME, PROGRAM_NAME_AND_VERSION, win.WS_OVERLAPPEDWINDOW, win.CW_USEDEFAULT,
			win.CW_USEDEFAULT, win.CW_USEDEFAULT, win.CW_USEDEFAULT, nil, nil, _win.hinstance, nil
		)

		assert(_win.hwnd != nil)
		if _win.hwnd == nil do return false

		win.ShowWindow(_win.hwnd, win.SW_SHOWDEFAULT)
		win.UpdateWindow(_win.hwnd) or_return

		imgui_win32.Init(_win.hwnd) or_return
		video_init_dx11(_win.hwnd) or_return

		// -----------------------------------------------------------------------
		// Tray icon
		// -----------------------------------------------------------------------
		data := win.NOTIFYICONDATAW {
			cbSize = size_of(win.NOTIFYICONDATAW),
			hWnd = _win.hwnd,
			uID = 1,
			uFlags = win.NIF_TIP|win.NIF_MESSAGE|win.NIF_ICON,
			uVersion = 4,
			hIcon = _win.icon,
			uCallbackMessage = win.WM_APP + 1,
		}

		tip :: PROGRAM_NAME_AND_VERSION
		copy(data.szTip[:len(data.szTip)-1], string16(tip))

		win.Shell_NotifyIconW(win.NIM_ADD, &data)

		_win.tray_menu = win.CreatePopupMenu()
		if _win.tray_menu != nil {
			win.AppendMenuW(_win.tray_menu, win.MF_STRING, TRAY_BUTTON_SHOW, "Show")
			win.AppendMenuW(_win.tray_menu, win.MF_STRING, TRAY_BUTTON_EXIT, "Exit")
		}

		return true
	}

	_platform_impl_destroy_window = proc() {
		if _win.hwnd != nil {
			// Tray icon
			if _win.tray_menu != nil {
				data := win.NOTIFYICONDATAW {
					cbSize = size_of(win.NOTIFYICONDATAW),
					hWnd = _win.hwnd,
					uID = 1,
				}

				win.Shell_NotifyIconW(win.NIM_DELETE, &data)
				win.DestroyMenu(_win.tray_menu)
			}

			// ImGui & window
			video_shutdown_dx11()
			imgui_win32.Shutdown()
			win.DestroyWindow(_win.hwnd)
		}
		_win.hwnd = nil
	}

	_platform_impl_is_window_visible = proc() -> bool {
		return _win.hwnd != nil && auto_cast win.IsWindowVisible(_win.hwnd)
	}

	_platform_impl_imgui_new_frame = proc() {
		imgui_win32.NewFrame()
	}

	_platform_impl_poll_events = proc() -> Platform_Events {
		msg: win.MSG
		for win.PeekMessageW(&msg, _win.hwnd, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		return _win.events
	}

	_platform_impl_set_gl_proc_address = proc(p: rawptr, name: cstring) {
		win.gl_set_proc_address(p, name)
	}

	_platform_impl_swap_buffers = proc() {
	}

	_win.hinstance = cast(win.HINSTANCE) win.GetModuleHandleW(nil)
	_win.icon = win.LoadIconW(_win.hinstance, "WindowIconLight")

	wndclass := win.WNDCLASSEXW {
		hInstance = _win.hinstance,
		lpszClassName = WINDOW_CLASS_NAME,
		cbSize = size_of(win.WNDCLASSEXW),
		lpfnWndProc = _wnd_proc,
		hIcon = _win.icon,
	}

	assert(win.RegisterClassExW(&wndclass) != 0)

	_win.tray_callback = tray_cb
	_win.tray_callback_data = tray_cbd

	return true
}

_wnd_proc :: proc "system" (
	hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM
) -> win.LRESULT {
	if imgui_win32.WndProcHandler(hwnd, msg, wparam, lparam) != 0 {
		return 1
	}

	switch msg {
	case win.WM_APP+1: {
		sub_msg := win.LOWORD(lparam)

		switch sub_msg {
		case win.WM_LBUTTONDOWN:
			win.ShowWindow(_win.hwnd, win.SW_SHOWDEFAULT)
		case win.WM_RBUTTONDOWN:
			mouse: win.POINT
			win.GetCursorPos(&mouse)
			win.TrackPopupMenu(_win.tray_menu, win.TPM_LEFTBUTTON, mouse.x, mouse.y, 0, _win.hwnd, nil)
			win.PostMessageW(_win.hwnd, win.WM_NULL, 0, 0)
		}

		return 0
	}
	case win.WM_COMMAND:
		switch wparam {
		case TRAY_BUTTON_SHOW:
			win.ShowWindow(_win.hwnd, win.SW_SHOWDEFAULT)
			win.BringWindowToTop(_win.hwnd)
		case TRAY_BUTTON_EXIT: _win.events.want_exit = true
		}
		return 0
	case win.WM_CLOSE:
		if hwnd == _win.hwnd do _win.events.window_closed = true
		return 0
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
