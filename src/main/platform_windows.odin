#+private file
package main

import win "core:sys/windows"
import imgui_win32 "src:thirdparty/odin-imgui/imgui_impl_win32"

_win: struct {
	hinstance: win.HINSTANCE,
	hwnd: win.HWND,
	gl: struct {
		hdc: win.HDC,
		hrc: win.HGLRC,
	},
	video_impl: Video_Impl,
}

@private
use_platform_win32 :: proc() {
	_platform_impl_init = proc() -> bool {
		if _win.hinstance == nil {
			_win.hinstance = cast(win.HINSTANCE) win.GetModuleHandleW(nil)

			wndclass := win.WNDCLASSEXW {
				hInstance = _win.hinstance,
				lpszClassName = "WINDOW_CLASS",
				cbSize = size_of(win.WNDCLASSEXW),
				lpfnWndProc = _wnd_proc,
			}

			assert(win.RegisterClassExW(&wndclass) != 0)
		}

		_win.hwnd = win.CreateWindowExW(
			0, "WINDOW_CLASS", "RAT MP", win.WS_OVERLAPPEDWINDOW, win.CW_USEDEFAULT,
			win.CW_USEDEFAULT, win.CW_USEDEFAULT, win.CW_USEDEFAULT, nil, nil, _win.hinstance, nil
		)

		assert(_win.hwnd != nil)
		if _win.hwnd == nil do return false

		win.ShowWindow(_win.hwnd, win.SW_SHOWDEFAULT)
		win.UpdateWindow(_win.hwnd)

		imgui_win32.Init(_win.hwnd)
		init_video_dx11(_win.hwnd)

		return true
	}

	_platform_impl_shutdown = proc() {
		imgui_win32.Shutdown()
		win.DestroyWindow(_win.hwnd)
		_win.hwnd = nil
	}

	_platform_impl_imgui_new_frame = proc() {
		imgui_win32.NewFrame()
	}

	_platform_impl_poll_events = proc() {
		msg: win.MSG
		for win.PeekMessageW(&msg, _win.hwnd, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}
	}

	_platform_impl_set_gl_proc_address = proc(p: rawptr, name: cstring) {
		win.gl_set_proc_address(p, name)
	}

	_platform_impl_swap_buffers = proc() {
	}
}

_wnd_proc :: proc "system" (
	hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM
) -> win.LRESULT {
	if imgui_win32.WndProcHandler(hwnd, msg, wparam, lparam) != 0 {
		return 0
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
