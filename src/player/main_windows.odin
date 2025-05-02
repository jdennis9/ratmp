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
	close_policy: config.Close_Policy,

	window_title_track_id: library.Track_ID,

	media_controls: struct {
		play: bool,
		prev: bool,
		next: bool,
		pause: bool,
	}
}

@private
_WNDCLASS_NAME := intrinsics.constant_utf16_cstring("RATMP_WINDOW_CLASS")

foreign import cpp_lib "../cpp/cpp.lib"

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
			this.media_controls.play = true
		}
		case .Pause: {
			this.media_controls.pause = true
		}
		case .Next: {
			this.media_controls.next = true
		}
		case .Prev: {
			this.media_controls.prev = true
		}
	}

	win.PostMessageW(this.hwnd, win.WM_USER, 0, 0)
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

apply_prefs :: proc(prefs: config.Preferences) {
	this.close_policy = prefs.close_policy
}

main :: proc() {
	run()
}

wake_proc :: proc() {
	win.PostMessageW(this.hwnd, win.WM_USER, 0, 0)
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
	
	this.icon = win.LoadIconA(this.hinstance, "WindowIconDarkTheme")
	
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
	
	com.init(&state, ".", ".", wake_proc) or_return
	defer com.shutdown()
	
	apply_prefs(state.prefs.values)
	
	if state.prefs.values.enable_media_controls {
		media_controls.install_handler(media_controls_handler)
		this.enable_media_controls = true
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

		if state.prefs.dirty {
			apply_prefs(state.prefs.values)
		}

		// Update window title to show playing track
		if state.playback.playing_track != this.window_title_track_id {
			buf: [256]u8
			this.window_title_track_id = state.playback.playing_track

			if state.playback.playing_track != 0 {
				track := library.get_track_info(state.library, state.playback.playing_track)
				set_window_title(fmt.bprint(buf[:], build.PROGRAM_NAME_AND_VERSION, "|", track.artist, "-", track.title))
			}
			else {
				set_window_title(build.PROGRAM_NAME_AND_VERSION)
			}
		}

		// Handle media controls
		if this.enable_media_controls {
			if this.media_controls.next {
				playback.play_next_track(&state.playback, state.library)
				this.media_controls.next = false
			}

			if this.media_controls.prev {
				playback.play_prev_track(&state.playback, state.library)
				this.media_controls.prev = false
			}

			if this.media_controls.pause {
				playback.set_paused(&state.playback, true)
				this.media_controls.pause = false
			}

			if this.media_controls.play {
				playback.set_paused(&state.playback, false)
				this.media_controls.play = false
			}

			sync_media_controls_state(state.playback, state.library)
		}
		
		// Update and render frame
		if !minimized && dx11.begin_frame() {
			this.running = com.frame()
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
				case .MinimizeToTray: {
					hide_window()
				}
				case .Exit: {
					this.running = false
				}
				case .AlwaysAsk: {
					if util.message_box("Minimize to tray?", .YesNo, 
					"Would you like me to keep running in the background? The default behaviour of this can be changed in your preferences.") {
						hide_window()
					}
					else {
						this.running = false
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
				this.running = false
			}
			return 0
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
