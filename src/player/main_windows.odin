/*
	RAT MP: A lightweight graphical music player
    Copyright (C) 2025 Jamie Dennis

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
package main_win32

import "base:runtime"
import "base:intrinsics"
import "core:log"
import win "core:sys/windows"
import "core:unicode/utf16"
import "core:fmt"
import "core:os"

import imgui_win32 "libs:odin-imgui/imgui_impl_win32"
import imgui "libs:odin-imgui"

import "player:util"
import com "player:main_common"
import dx11 "player:video/dx11"
import "player:media_controls"
import "player:playback"
import "player:library"
import "player:build"
import "player:drag_drop"
import "player:config"
import "player:ui"
//import "player:audio"

@private
_windows: struct {
	hwnd: win.HWND,
	hinstance: win.HINSTANCE,
	ctx: runtime.Context,
	resize_width, resize_height: int,
	icon: win.HICON,
	tray_popup: win.HMENU,
	running: bool,
	enable_media_controls: bool,
	close_policy: config.Close_Policy,
	
	window_title_track_id: library.Track_ID,

	minimize_to_tray: bool,
	
	media_controls: struct {
		play: bool,
		prev: bool,
		next: bool,
		pause: bool,
	}
}
state: com.State

@private
_WNDCLASS_NAME := intrinsics.constant_utf16_cstring("RATMP_WINDOW_CLASS")

foreign import cpp_lib "../cpp/cpp.lib"

foreign cpp_lib {
	ole_initialize :: proc() -> win.HRESULT ---
	dwm_set_dark_title_bar :: proc(hwnd: rawptr, on: bool) ---
	is_system_light_theme :: proc() -> bool ---
}


apply_prefs :: proc(prefs: config.Preferences) {
	_windows.close_policy = prefs.close_policy
}

main :: proc() {
	run()
}

wake_proc :: proc() {
	win.PostMessageW(_windows.hwnd, win.WM_USER, 0, 0)
}

run :: proc() -> bool {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger()
	}
	else {
		log_file, log_file_error := util.overwrite_file("log.txt")
		context.logger = log.create_file_logger(log_file)
		log.info("======================= Beginning of log =======================" )
	}

	imgui_win32.EnableDpiAwareness()

	use_light_theme := is_system_light_theme()
	_windows.ctx = context
	
	imgui.CreateContext()
	defer imgui.DestroyContext()

	ole_initialize()
	win.CoInitializeEx(nil, .MULTITHREADED)
	_windows.hinstance = auto_cast win.GetModuleHandleW(nil)
	
	_windows.icon = win.LoadIconA(_windows.hinstance, use_light_theme ? "WindowIconLightTheme" : "WindowIconDarkTheme")
	
	{
		wndclass := win.RegisterClassExW(&win.WNDCLASSEXW{
			hInstance = _windows.hinstance,
			style = win.CS_OWNDC,
			lpszClassName = _WNDCLASS_NAME,
			lpfnWndProc = win_proc,
			cbSize = size_of(win.WNDCLASSEXW),
			hIcon = _windows.icon,
		})
		
		assert(wndclass != 0)
		
		_windows.hwnd = win.CreateWindowExW(
			win.WS_EX_ACCEPTFILES,
			//0,
			_WNDCLASS_NAME, 
			intrinsics.constant_utf16_cstring(build.PROGRAM_NAME_AND_VERSION),
			win.WS_OVERLAPPEDWINDOW,
			100, 100, win.CW_USEDEFAULT, win.CW_USEDEFAULT, 
			nil, nil, _windows.hinstance, nil
		)
	}
	
	if (os.is_windows_10() || os.is_windows_11()) && !use_light_theme {
		dwm_set_dark_title_bar(_windows.hwnd, true)
	}
	win.UpdateWindow(_windows.hwnd)
	win.ShowWindow(_windows.hwnd, win.SW_HIDE)
	
	// Renderer
	dx11.init_for_windows(_windows.hwnd)
	defer dx11.shutdown_for_windows()
	
	// Drag-drop
	drag_drop.init(_windows.hwnd, drag_drop_callback)

	// System tray
	add_tray_icon()
	defer remove_tray_icon()
	
	com.init(&state, ".", ".", wake_proc) or_return
	defer com.shutdown()
	
	apply_prefs(state.prefs.values)
	
	if state.prefs.values.enable_media_controls {
		media_controls.install_handler(media_controls_handler)
		_windows.enable_media_controls = true
	}

	update_scaling()

	visible := true
	show_window()

	_windows.running = true
	for _windows.running {
		msg: win.MSG

		if _windows.minimize_to_tray {
			win.ShowWindow(_windows.hwnd, win.SW_HIDE)
			_windows.minimize_to_tray = false
		}

		minimized := !win.IsWindowVisible(_windows.hwnd)

		if visible && !minimized {
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

		if !_windows.running {break}
	
		if _windows.resize_width != 0 {
			dx11.resize_window(_windows.resize_width, _windows.resize_height)
			_windows.resize_width = 0
			_windows.resize_height = 0
		}

		if state.prefs.dirty {
			apply_prefs(state.prefs.values)
		}

		
		// Handle media controls
		if _windows.enable_media_controls {
			if _windows.media_controls.next {
				playback.play_next_track(&state.playback, state.library)
				_windows.media_controls.next = false
			}

			if _windows.media_controls.prev {
				playback.play_prev_track(&state.playback, state.library)
				_windows.media_controls.prev = false
			}
			
			if _windows.media_controls.pause {
				playback.set_paused(&state.playback, true)
				_windows.media_controls.pause = false
			}

			if _windows.media_controls.play {
				playback.set_paused(&state.playback, false)
				_windows.media_controls.play = false
			}

		}
		
		sync_media_controls_state(state.playback, state.library)

		com.handle_events()

		// Update window title to show playing track
		if state.playback.playing_track != _windows.window_title_track_id {
			buf: [256]u8
			_windows.window_title_track_id = state.playback.playing_track

			if state.playback.playing_track != 0 {
				track := library.get_track_info(state.library, state.playback.playing_track)
				set_window_title(fmt.bprint(buf[:], build.PROGRAM_NAME_AND_VERSION, "|", track.artist, "-", track.title))
			}
			else {
				set_window_title(build.PROGRAM_NAME_AND_VERSION)
			}
		}

		
		// Update and render frame
		if !minimized && dx11.begin_frame() {
			_windows.running, _windows.minimize_to_tray = com.frame()
			visible = dx11.present()
		}
	}

	return true
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> int {
	context = _windows.ctx

	if (imgui_win32.WndProcHandler(hwnd, msg, wparam, lparam) != 0) {
		return 1
	}

	switch msg {
		case win.WM_SIZE: {
			_windows.resize_width = int(win.LOWORD(lparam))
			_windows.resize_height = int(win.HIWORD(lparam))
		}
		case win.WM_CLOSE: {
			switch _windows.close_policy {
				case .MinimizeToTray: {
					hide_window()
				}
				case .Exit: {
					_windows.running = false
				}
				case .AlwaysAsk: {
					if util.message_box("Minimize to tray?", .YesNo, 
					"Would you like me to keep running in the background? The default behaviour of this can be changed in your preferences.") {
						hide_window()
					}
					else {
						_windows.running = false
					}
				}
			}

			return 0
		}
		case win.WM_APP + 1: {
			if win.LOWORD(lparam) == win.WM_LBUTTONDOWN {
				show_window()
			}
			else if (win.LOWORD(lparam) == win.WM_RBUTTONDOWN) {
				mouse: win.POINT
				win.GetCursorPos(&mouse)
				win.TrackPopupMenu(_windows.tray_popup, win.TPM_LEFTBUTTON, mouse.x, mouse.y, 0, _windows.hwnd, nil)
				win.PostMessageW(_windows.hwnd, win.WM_NULL, 0, 0)
			}
			return 0
		}
		case win.WM_COMMAND: {
			if wparam == 1 {
				_windows.running = false
			}
			return 0
		}
		case win.WM_DPICHANGED: {
			rect := cast(^win.RECT) cast(uintptr) lparam
			win.SetWindowPos(hwnd, nil, 
				rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, 
				win.SWP_NOZORDER
			)
			update_scaling()
			return 0
		}
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

hide_window :: proc() {
	win.ShowWindow(_windows.hwnd, win.SW_HIDE)
}

show_window :: proc() {
	win.ShowWindow(_windows.hwnd, win.SW_SHOWDEFAULT)
	win.SetForegroundWindow(_windows.hwnd)
}

add_tray_icon :: proc() {
	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = _windows.hwnd,
		uID = 1,
		uFlags = win.NIF_TIP|win.NIF_MESSAGE|win.NIF_ICON,
		uCallbackMessage = win.WM_APP + 1,
		uVersion = 4,
		hIcon = _windows.icon,
	}

	tip :: build.PROGRAM_NAME
	copy(data.szTip[:], intrinsics.constant_utf16_cstring(tip)[:len(tip)])

	win.Shell_NotifyIconW(win.NIM_ADD, &data)

	_windows.tray_popup = win.CreatePopupMenu()
	if _windows.tray_popup != nil {
		win.AppendMenuW(_windows.tray_popup, win.MF_STRING, 1, intrinsics.constant_utf16_cstring("Exit"))
	}
}

remove_tray_icon :: proc() {
	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = _windows.hwnd,
		uID = 1,
	}

	win.Shell_NotifyIconW(win.NIM_DELETE, &data)

	if _windows.tray_popup != nil {
		win.DestroyMenu(_windows.tray_popup)
	}
}


set_window_title :: proc(title: string) {
	buf: [256]u16

	utf16.encode_string(buf[:254], title)
	win.SetWindowTextW(_windows.hwnd, raw_data(buf[:]))
}

media_controls_handler :: proc "c" (event: media_controls.Event) {
	context = _windows.ctx

	switch event {
		case .Play: {
			_windows.media_controls.play = true
		}
		case .Pause: {
			_windows.media_controls.pause = true
		}
		case .Next: {
			_windows.media_controls.next = true
		}
		case .Prev: {
			_windows.media_controls.prev = true
		}
	}

	win.PostMessageW(_windows.hwnd, win.WM_USER, 0, 0)
}

sync_media_controls_state :: proc(pb: playback.State, lib: library.Library) {
	@static displayed_track_id: library.Track_ID
	@static displayed_status: media_controls.Status

	if pb.playing_track != 0 && displayed_track_id != pb.playing_track {
		track := library.get_track_info(lib, pb.playing_track)
		media_controls.set_metadata(track.album, track.artist, track.title)
	}

	status: media_controls.Status

	if pb.playing_track == 0 {
		status = .Stopped
	}
	else {
		status = pb.paused ? .Paused : .Playing
	}

	if status != displayed_status {
		displayed_status = status
		media_controls.set_status(status)
	}
}

drag_drop_callback :: proc "c" (path: cstring) {
	context = _windows.ctx
	ui.queue_file_for_scanning(&state.ui, string(path))
}

update_scaling :: proc() {
	style := imgui.GetStyle()
	scale := imgui_win32.GetDpiScaleForHwnd(_windows.hwnd)
	imgui.Style_ScaleAllSizes(style, scale)
	style.WindowBorderSize = 1
	style.ChildBorderSize = 1
	style.PopupBorderSize = 1
	style.FrameBorderSize = 1
	style.TabBorderSize = 1

	dx11.invalidate_imgui_objects()

	state.ui.dpi_scale = scale
	ui.apply_prefs(&state.ui, state.prefs.values, force_load_font=true)

	dx11.create_imgui_objects()
}
