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
#+private file
package main

import "core:unicode/utf16"
import win "core:sys/windows"
import imgui_win32 "src:thirdparty/odin-imgui/imgui_impl_win32"



WINDOW_CLASS_NAME :: PROGRAM_ID + "_window_class"


_win: struct {
	hinstance: win.HINSTANCE,
	hwnd:      win.HWND,
	events:    Platform_Events,
	icon:      win.HICON,
	resize:    Maybe([2]int),
}

@private
platform_init_win32 :: proc() -> bool {
	_platform_impl_shutdown = proc() {
		win.UnregisterClassW(WINDOW_CLASS_NAME, _win.hinstance)
	}

	_platform_impl_make_window = proc() -> bool {
		_win.hwnd = win.CreateWindowExW(
			0, WINDOW_CLASS_NAME, PROGRAM_NAME_AND_VERSION, win.WS_OVERLAPPEDWINDOW, win.CW_USEDEFAULT,
			win.CW_USEDEFAULT, win.CW_USEDEFAULT, win.CW_USEDEFAULT, nil, nil, _win.hinstance, nil
		)

		if _win.hwnd == nil do return false

		// Dark mode
		{
			on: win.BOOL = true
			win.DwmSetWindowAttribute(_win.hwnd, 
				auto_cast win.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE,
				&on, size_of(on)
			)
		}

		win.ShowWindow(_win.hwnd, win.SW_SHOW)
		win.UpdateWindow(_win.hwnd) or_return

		imgui_win32.Init(_win.hwnd) or_return
		video_dx11_init(_win.hwnd) or_return

		return true
	}

	_platform_impl_destroy_window = proc() {
		if _win.hwnd != nil {		
			video_shutdown_dx11()
			imgui_win32.Shutdown()
			win.DestroyWindow(_win.hwnd)
		}
		_win.hwnd = nil
	}

	_platform_impl_is_window_visible = proc() -> bool {
		return _win.hwnd != nil && auto_cast win.IsWindowVisible(_win.hwnd)
	}

	_platform_impl_set_window_visible = proc(visible: bool) {
		if visible {
			win.ShowWindow(_win.hwnd, win.SW_SHOWDEFAULT)
		}
		else {
			win.ShowWindow(_win.hwnd, win.SW_HIDE)
		}
	}

	_platform_impl_imgui_new_frame = proc() {
		imgui_win32.NewFrame()
	}

	_platform_impl_poll_events = proc() -> Platform_Events {
		msg: win.MSG
		_win.events = {}
		for win.PeekMessageW(&msg, _win.hwnd, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		if _win.resize != nil {
			rs := _win.resize.?
			video_resize_swapchain(rs.x, rs.y)
		}

		return _win.events
	}

	_platform_impl_wait_events = proc() -> Platform_Events {
		win.WaitMessage()
		return platform_poll_events()
	}

	_platform_impl_flush_events = proc() {
		if _win.hwnd != nil {
			win.PostMessageW(_win.hwnd, win.WM_NULL, 0, 0)
		}
	}

	_platform_impl_swap_buffers = proc() {
	}

	_platform_impl_set_window_title = proc(title: cstring) {
		buf: [1024]u16
		if _win.hwnd != nil {
			utf16.encode_string(buf[:1023], string(title))
			win.SetWindowTextW(_win.hwnd, cstring16(&buf[0]))
		}
	}

	_platform_impl_set_window_size = proc(w, h: int) {
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

	return true
}

_wnd_proc :: proc "system" (
	hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM
) -> win.LRESULT {
	if imgui_win32.WndProcHandler(hwnd, msg, wparam, lparam) != 0 {
		return 1
	}

	switch msg {
	case win.WM_CLOSE:
		if hwnd == _win.hwnd do _win.events.window_closed = true
		return 0
	case win.WM_SIZE:
		_win.resize = [2]int {
			auto_cast win.LOWORD(lparam),
			auto_cast win.HIWORD(lparam),
		}
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
