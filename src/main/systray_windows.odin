#+private file
package main

import "core:sync"
import "core:thread"
import "core:log"
import "base:runtime"
import win "core:sys/windows"

WINDOW_CLASS_NAME :: PROGRAM_ID + "_systray"

_win_systray: struct {
	hinstance: win.HINSTANCE,
	hwnd: win.HWND,
	icon: win.HICON,
	callback: Sys_Tray_Proc,
	callback_data: rawptr,
	tray_menu: win.HMENU,
	background_thread: ^thread.Thread,
	want_destroy: bool,
	error: bool,
	ready_event: sync.Auto_Reset_Event,
	ctx: runtime.Context,
}

TRAY_BUTTON_SHOW :: 0
TRAY_BUTTON_EXIT :: 1

@private
systray_use_win32 :: proc() {
	_systray_impl_create = proc(cb: Sys_Tray_Proc, cbd: rawptr) -> bool {
		s := &_win_systray
		s.callback = cb
		s.callback_data = cbd
		s.error = false
		s.background_thread = thread.create(_background_thread_proc, .Low)
		s.background_thread.init_context = context
		thread.start(s.background_thread)

		log.debug("Waiting for system tray initialization...")
		sync.auto_reset_event_wait(&s.ready_event)
		if s.error {
			log.debug("Error creating tray icon")
			return false
		}

		return true
	}

	_systray_impl_destroy = proc() {
		s := &_win_systray

		if s.background_thread != nil {
			s.want_destroy = true
			if s.hwnd != nil {
				win.PostMessageW(s.hwnd, win.WM_NULL, 0, 0)
			}
			thread.join(s.background_thread)
			thread.destroy(s.background_thread)
			s.want_destroy = false
		}

		if s.tray_menu != nil {
			data := win.NOTIFYICONDATAW {
				cbSize = size_of(win.NOTIFYICONDATAW),
				hWnd = s.hwnd,
				uID = 1,
			}

			win.Shell_NotifyIconW(win.NIM_DELETE, &data)
			win.DestroyMenu(s.tray_menu)
			s.tray_menu = nil
		}

		if s.hwnd != nil {
			win.DestroyWindow(s.hwnd)
			s.hwnd = nil
		}
	}

	wndclass := win.WNDCLASSEXW {
		cbSize = size_of(win.WNDCLASSEXW),
		lpfnWndProc = _wnd_proc,
		lpszClassName = WINDOW_CLASS_NAME,
	}

	assert(win.RegisterClassExW(&wndclass) != 0)

	_win_systray.hinstance = auto_cast win.GetModuleHandleW(nil)
	_win_systray.icon = win.LoadIconW(_win_systray.hinstance, "WindowIconLight")
}

_wnd_proc :: proc "system" (
	hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM
) -> win.LRESULT {
	s := &_win_systray
	context = s.ctx

	switch msg {
	case win.WM_APP+1: {
		sub_msg := win.LOWORD(lparam)

		switch sub_msg {
		case win.WM_LBUTTONDOWN:
			s.callback(s.callback_data, .Show)
		case win.WM_RBUTTONDOWN:
			mouse: win.POINT
			log.debug("Waga")
			win.GetCursorPos(&mouse)
			win.TrackPopupMenu(s.tray_menu, win.TPM_LEFTBUTTON, mouse.x, mouse.y, 0, s.hwnd, nil)
			win.PostMessageW(s.hwnd, win.WM_NULL, 0, 0)
		}

		return 0
	}
	case win.WM_COMMAND:
		switch wparam {
		case TRAY_BUTTON_SHOW:
			s.callback(s.callback_data, .Show)
		case TRAY_BUTTON_EXIT:
			s.callback(s.callback_data, .Exit)
		}
		return 0
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

_background_thread_proc :: proc(t: ^thread.Thread) {
	msg: win.MSG
	s := &_win_systray

	defer if s.error {
		sync.auto_reset_event_signal(&s.ready_event)
	}

	// Create dummy window
	s.hwnd = win.CreateWindowExW(
		0, WINDOW_CLASS_NAME, WINDOW_CLASS_NAME,
		0, 0, 0, 0, 0, nil, nil, s.hinstance, nil
	)
	win.UpdateWindow(s.hwnd)

	if s.hwnd == nil {
		log.error("Failed to create dummy window")
		s.error = true
		return
	}

	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = s.hwnd,
		uID = 1,
		uFlags = win.NIF_TIP|win.NIF_MESSAGE|win.NIF_ICON,
		uVersion = 4,
		hIcon = s.icon,
		uCallbackMessage = win.WM_APP + 1,
	}

	tip :: PROGRAM_NAME_AND_VERSION
	copy(data.szTip[:len(data.szTip)-1], string16(tip))

	if !win.Shell_NotifyIconW(win.NIM_ADD, &data) {
		s.error = true
		return
	}

	s.tray_menu = win.CreatePopupMenu()
	if s.tray_menu != nil {
		win.AppendMenuW(s.tray_menu, win.MF_STRING, TRAY_BUTTON_SHOW, "Show")
		win.AppendMenuW(s.tray_menu, win.MF_STRING, TRAY_BUTTON_EXIT, "Exit")
	}

	sync.auto_reset_event_signal(&s.ready_event)

	log.debug("Running system tray listener")

	for {
		if win.GetMessageW(&msg, s.hwnd, 0, 0) != 0 {
			if s.want_destroy {
				return
			}

			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}
	}
}
