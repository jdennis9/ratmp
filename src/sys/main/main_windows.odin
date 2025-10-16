package sys_main

import "base:runtime"
import win "core:sys/windows"
import "core:unicode/utf16"

import imgui_win32 "src:thirdparty/odin-imgui/imgui_impl_win32"
import imgui_dx11 "src:thirdparty/odin-imgui/imgui_impl_dx11"

import "src:build"
import "src:server"
import "src:client"
import "src:sys"
import misc "src:bindings/windows_misc"

@private
_win32: struct {
	ctx: runtime.Context,
	hinstance: win.HINSTANCE,
	hwnd: win.HWND,
	tray_popup: win.HMENU,
	icon: win.HICON,
	resize_width, resize_height: int,
	width, height: int,
	need_reload_font: bool,
	dpi_scale: f32,
	running: bool,
	title_track_id: server.Track_ID,
	drag_drop_payload: [dynamic]sys.Path,
	drag_drop_done: bool,
	obscured: bool,
	sv: ^server.Server,
	cl: ^client.Client,
}

init :: proc(sv: ^server.Server, cl: ^client.Client) -> (data_dir, config_dir: string, ok: bool) {
	sys.audio_use_backend(.Wasapi)
	
	_win32.sv = sv
	_win32.cl = cl
	_win32.ctx = context
	_win32.hinstance = auto_cast win.GetModuleHandleW(nil)
	_win32.icon = win.LoadIconA(_win32.hinstance, "WindowIconLight")
	misc.ole_initialize()

	data_dir = "."
	config_dir = "."

	ok = true
	return
}

create_window :: proc() -> bool {
	imgui_win32.EnableDpiAwareness()

	wndclass_name := cstring16("WINDOW_CLASS")

	win.RegisterClassExW(&win.WNDCLASSEXW{
		hInstance = _win32.hinstance,
		style = win.CS_OWNDC,
		lpszClassName = wndclass_name,
		lpfnWndProc = _win_proc,
		cbSize = size_of(win.WNDCLASSEXW),
		hIcon = _win32.icon,
	})
	
	_win32.hwnd = win.CreateWindowExW(
		win.WS_EX_ACCEPTFILES,
		wndclass_name,
		win.L(build.PROGRAM_NAME_AND_VERSION),
		win.WS_OVERLAPPEDWINDOW,
		100, 100, win.CW_USEDEFAULT, win.CW_USEDEFAULT,
		nil, nil, _win32.hinstance, nil
	)
	
	{
		on: win.BOOL = true
		win.DwmSetWindowAttribute(_win32.hwnd, DWMA_USE_IMMERSIVE_DARK_MODE, &on, size_of(on))
	}
	
	win.UpdateWindow(_win32.hwnd)
	win.ShowWindow(_win32.hwnd, win.SW_HIDE)
	_add_tray_icon()
	misc.drag_drop_init(_win32.hwnd, _drag_drop_drop)

	imgui_win32.Init(_win32.hwnd)
	sys._dx11_init(_win32.hwnd)

	sys._set_hdc(win.GetDC(_win32.hwnd))

	_win32.running = true

	return true
}

present :: proc() {
	_win32.obscured = sys._dx11_present()
}

shutdown :: proc() {
	sys._dx11_destroy()
	win.DestroyWindow(_win32.hwnd)
	imgui_win32.Shutdown()
	_remove_tray_icon()
}

new_frame :: proc() {
	sys._dx11_clear_buffer()

	imgui_win32.NewFrame()
	imgui_dx11.NewFrame()
}

// Return false to terminate program
handle_events :: proc() -> bool {
	msg: win.MSG

	window_is_visible := win.IsWindowVisible(_win32.hwnd) && !win.IsIconic(_win32.hwnd)
	
	// Handle events
	if window_is_visible && !_win32.obscured {
		for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}
	}
	else {
		win.GetMessageW(&msg, nil, 0, 0)
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}

	if _win32.drag_drop_done {
		server.queue_files_for_scanning(_win32.sv, _win32.drag_drop_payload[:])
		delete(_win32.drag_drop_payload)
		_win32.drag_drop_payload = nil
		_win32.drag_drop_done = false
	}

	if _win32.resize_height != 0 {
		sys._dx11_resize_swapchain(_win32.resize_width, _win32.resize_height)
		_win32.resize_width = 0
		_win32.resize_height = 0
	}

	return _win32.running
}

show_window :: proc(show: bool) {
	if show {
		win.ShowWindow(_win32.hwnd, win.SW_SHOWDEFAULT)
	}
	else {
		win.ShowWindow(_win32.hwnd, win.SW_HIDE)
	}
}

post_empty_event :: proc() {
	win.PostMessageW(_win32.hwnd, win.WM_NULL, 0, 0)
}

set_window_title :: proc(title: string) {
	buf_u16: [256]u16
	utf16.encode_string(buf_u16[:len(buf_u16)-1], title)
	win.SetWindowTextW(_win32.hwnd, cstring16(&buf_u16[0]))
}
