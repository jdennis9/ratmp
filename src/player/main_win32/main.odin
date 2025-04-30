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

import imgui_win32 "libs:odin-imgui/imgui_impl_win32"
import imgui "libs:odin-imgui"

import "player:util"
import com "player:main_common"
import dx11 "player:video/dx11"
import "player:signal"
import "player:media_controls"
import "player:playback"
import "player:library"
import "player:build"
import "player:drag_drop"
import "player:config"

@private
this: struct {
	hwnd: win.HWND,
	hinstance: win.HINSTANCE,
	ctx: runtime.Context,
	resize_width, resize_height: int,
	icon: win.HICON,
	tray_popup: win.HMENU,
	running: bool,
	enable_media_controls: bool,
	close_policy: int,
}

@private
_WNDCLASS_NAME := intrinsics.constant_utf16_cstring("RATMP_WINDOW_CLASS")

@private
ICON_DATA := #load("../resources/32x32.ico")

foreign import cpp_lib "../../cpp/cpp.lib"

foreign cpp_lib {
	ole_initialize :: proc() -> win.HRESULT ---
	dwm_set_dark_title_bar :: proc(hwnd: rawptr, on: bool) ---
}

set_window_title :: proc(title: string) {
	buf: [256]u16
	length: int

	utf16.encode_string(buf[:254], title)
	win.SetWindowTextW(this.hwnd, raw_data(buf[:]))
}

media_controls_handler :: proc "c" (event: media_controls.Event) {
	context = this.ctx

	switch event {
		case .Play: {
			signal.post(.RequestPlay)
		}
		case .Pause: {
			signal.post(.RequestPause)
		}
		case .Next: {
			signal.post(.RequestNext)
		}
		case .Prev: {
			signal.post(.RequestPrev)
		}
	}

	win.PostMessageW(this.hwnd, win.WM_USER, 0, 0)
}

signal_post_callback :: proc(sig: signal.Signal) {
	win.PostMessageW(this.hwnd, win.WM_USER, auto_cast sig, 0)
}

@private
_media_controls_signal_handler :: proc(sig: signal.Signal) {
	/*if sig == .PlaybackStopped {
		media_controls.set_status(.Stopped)
	}
	else if sig == .TrackChanged {
		track_id := playback.get_playing_track()
		track := library.get_track_info(track_id)
		media_controls.set_metadata(track.album, track.artist, track.title)
	}
	else if sig == .PlaybackStateChanged {
		if playback.is_paused() {
			media_controls.set_status(.Paused)
		}
		else {
			media_controls.set_status(.Playing)
		}
	}*/
}

signal_handler :: proc(sig: signal.Signal) {
	/*if sig == .TrackChanged {
		track_id := playback.get_playing_track()
		track := library.get_track_info(track_id)

		buf: [256]u8
		set_window_title(fmt.bprint(buf[:], build.PROGRAM_NAME_AND_VERSION, "|", track.artist, "-", track.title))
	}
	else if sig == .PlaybackStopped {
		buf: [256]u8
		set_window_title(fmt.bprint(buf[:], build.PROGRAM_NAME_AND_VERSION))
	}
	else if sig == .ApplyPrefs {
		if prefs.prefs.choices[.EnableWindowsMediaControls] == 1 {
			media_controls.install_handler(media_controls_handler)
			signal.install_handler(_media_controls_signal_handler)
		}
	}
	else if sig == .Exit {
		this.running = false
	}*/
}

main :: proc() {
	run()
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

	state: com.State
	this.ctx = context
	
	imgui.CreateContext()
	defer imgui.DestroyContext()

	ole_initialize()
	win.CoInitializeEx(nil, .MULTITHREADED)
	this.hinstance = auto_cast win.GetModuleHandleW(nil)
	
	signal.init(signal_post_callback)
	signal.install_handler(signal_handler)
	
	this.icon = win.LoadIconA(this.hinstance, "WindowIcon")
	
	{
		wndclass := win.RegisterClassExW(&win.WNDCLASSEXW{
			hInstance = this.hinstance,
			style = win.CS_OWNDC,
			lpszClassName = _WNDCLASS_NAME,
			lpfnWndProc = win_proc,
			cbSize = size_of(win.WNDCLASSEXW),
			hIcon = this.icon,
		})
		
		assert(wndclass != 0)
		
		this.hwnd = win.CreateWindowExW(
			win.WS_EX_ACCEPTFILES,
			//0,
			_WNDCLASS_NAME, 
			intrinsics.constant_utf16_cstring(build.PROGRAM_NAME_AND_VERSION),
			win.WS_OVERLAPPEDWINDOW,
			100, 100, win.CW_USEDEFAULT, win.CW_USEDEFAULT, 
			nil, nil, this.hinstance, nil
		)
	}
	
	dwm_set_dark_title_bar(this.hwnd, true)
	win.UpdateWindow(this.hwnd)
	win.ShowWindow(this.hwnd, win.SW_HIDE)
	
	dx11.init_for_windows(this.hwnd)
	defer dx11.shutdown_for_windows()
	
	drag_drop.init_for_windows(this.hwnd)
	add_tray_icon()
	defer remove_tray_icon()
	
	com.init(&state, ".", ".") or_return
	defer com.shutdown()

	// Flush signal events
	{
		msg: win.MSG
		for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}
	}
	
	visible := true
	show_window()

	this.running = true
	for this.running {
		msg: win.MSG
		minimized := !win.IsWindowVisible(this.hwnd)

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
	
		if this.resize_width != 0 {
			dx11.resize_window(this.resize_width, this.resize_height)
			this.resize_width = 0
			this.resize_height = 0
		}

		com.handle_events()

		if !minimized && dx11.begin_frame() {
			com.frame()
			visible = dx11.present()
		}
	}

	return true
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> int {
	context = this.ctx

	if (imgui_win32.WndProcHandler(hwnd, msg, wparam, lparam) != 0) {
		return 1
	}

	switch msg {
		case win.WM_SIZE: {
			this.resize_width = int(win.LOWORD(lparam))
			this.resize_height = int(win.HIWORD(lparam))
		}
		case win.WM_CLOSE: {
			switch this.close_policy {
				case config.CLOSE_POLICY_MINIMIZE_TO_TRAY: {
					hide_window()
				}
				case config.CLOSE_POLICY_CLOSE: {
					signal.post(.Exit)
				}
				case: {
					if util.message_box("Minimize to tray?", .YesNo, 
					"Would you like me to keep running in the background? The default behaviour of this can be changed in your preferences.") {
						hide_window()
					}
					else {
						signal.post(.Exit)
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
				win.TrackPopupMenu(this.tray_popup, win.TPM_LEFTBUTTON, mouse.x, mouse.y, 0, this.hwnd, nil)
				win.PostMessageW(this.hwnd, win.WM_NULL, 0, 0)
			}
			return 0
		}
		case win.WM_COMMAND: {
			if wparam == 1 {
				signal.post(.Exit)
			}
			return 0
		}

		case win.WM_USER: {
			sig := cast(signal.Signal) wparam
			if sig != .None && sig <= max(signal.Signal) {
				signal.broadcast_immediate(sig)
			}
		}
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

hide_window :: proc() {
	win.ShowWindow(this.hwnd, win.SW_HIDE)
}

show_window :: proc() {
	win.ShowWindow(this.hwnd, win.SW_SHOWDEFAULT)
	win.SetForegroundWindow(this.hwnd)
}

add_tray_icon :: proc() {
	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = this.hwnd,
		uID = 1,
		uFlags = win.NIF_TIP|win.NIF_MESSAGE|win.NIF_ICON,
		uCallbackMessage = win.WM_APP + 1,
		uVersion = 4,
		hIcon = this.icon,
	}

	tip :: build.PROGRAM_NAME
	copy(data.szTip[:], intrinsics.constant_utf16_cstring(tip)[:len(tip)])

	win.Shell_NotifyIconW(win.NIM_ADD, &data)

	this.tray_popup = win.CreatePopupMenu()
	if this.tray_popup != nil {
		win.AppendMenuW(this.tray_popup, win.MF_STRING, 1, intrinsics.constant_utf16_cstring("Exit"))
	}
}

remove_tray_icon :: proc() {
	data := win.NOTIFYICONDATAW {
		cbSize = size_of(win.NOTIFYICONDATAW),
		hWnd = this.hwnd,
		uID = 1,
	}

	win.Shell_NotifyIconW(win.NIM_DELETE, &data)

	if this.tray_popup != nil {
		win.DestroyMenu(this.tray_popup)
	}
}
