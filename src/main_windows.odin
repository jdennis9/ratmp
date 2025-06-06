package main

import "base:runtime"
import win "core:sys/windows"
import "core:log"
import "core:mem"
import "core:fmt"
import "core:unicode/utf16"
import "core:time"
import "core:sync"
import "core:os"

import imgui "thirdparty/odin-imgui"
import imgui_dx11 "thirdparty/odin-imgui/imgui_impl_dx11"
import imgui_win32 "thirdparty/odin-imgui/imgui_impl_win32"

import dx11 "vendor:directx/d3d11"
import "vendor:directx/dxgi"

import drag_drop "src:bindings/windows_drag_drop"
import "build"
import "server"
import "client"

DWMA_USE_IMMERSIVE_DARK_MODE :: 20
TRAY_BUTTON_SHOW :: 1
TRAY_BUTTON_EXIT :: 2

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

	d3d: struct {
		device: ^dx11.IDevice,
		ctx: ^dx11.IDeviceContext,
		render_target: ^dx11.IRenderTargetView,
		swapchain: ^dxgi.ISwapChain,
	},

	drag_drop_payload: [dynamic]server.Path,
	drag_drop_done: bool,
}

wake_proc :: proc() {
	win.PostMessageW(_win32.hwnd, win.WM_USER, 0, 0)
}

server_event_handler :: proc(sv: server.Server, data: rawptr, event: server.Event) {
	#partial switch v in event {
		case server.Current_Track_Changed_Event: {
			if _win32.title_track_id != v.track_id {
			_win32.title_track_id = v.track_id
				if md, track_found := server.library_get_track_metadata(sv.library, v.track_id); track_found {
					buf: [256]u8
					title := fmt.bprint(buf[:255], build.PROGRAM_NAME_AND_VERSION, "|",
						md.values[.Artist].(string) or_else "",
						"-",
						md.values[.Title].(string) or_else ""
					)
					set_window_title(title)
				}
			}
		}
	}
}

run :: proc() -> bool {
	@static sv: server.Server
	@static ui: client.Client

	_win32.ctx = context
	_win32.hinstance = auto_cast win.GetModuleHandleW(nil)

	imgui_win32.EnableDpiAwareness()
	
	wndclass_name := win.L("WINDOW_CLASS")
	_win32.icon = win.LoadIconA(_win32.hinstance, "WindowIconLight")
	
	drag_drop.ole_initialize()

	// Create window
	win.RegisterClassExW(&win.WNDCLASSEXW{
		hInstance = _win32.hinstance,
		style = win.CS_OWNDC,
		lpszClassName = wndclass_name,
		lpfnWndProc = win_proc,
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
	add_tray_icon()
	defer remove_tray_icon()
	drag_drop.init(_win32.hwnd, drag_drop_drop)
	_win32.dpi_scale = imgui_win32.GetDpiScaleForHwnd(_win32.hwnd)

	// Video
	_init_dx11()
	defer _clean_up_dx11()
	
	// ImGui
	imgui.CreateContext()
	defer imgui.DestroyContext()
	imgui_win32.Init(_win32.hwnd)
	defer imgui_win32.Shutdown()
	imgui_dx11.Init(_win32.d3d.device, _win32.d3d.ctx)
	defer imgui_dx11.Shutdown()

	// Client
	client.init(&ui, &sv, create_imgui_texture, destroy_imgui_texture, ".", ".", wake_proc)
	defer client.destroy(&ui)
	set_ui_scale(_win32.dpi_scale)
	
	// Server
	server.init(&sv, wake_proc, ".", ".") or_return
	defer server.clean_up(&sv)
	server.add_event_handler(&sv, server_event_handler, nil)
	
	// Main loop
	win.ShowWindow(_win32.hwnd, win.SW_SHOWDEFAULT)
	_win32.running = true
	obscured: bool
	prev_frame_start: time.Tick

	for _win32.running {
		msg: win.MSG
		frame_start := time.tick_now()
		defer prev_frame_start = frame_start
		
		paused := server.is_paused(sv)
		window_is_visible := win.IsWindowVisible(_win32.hwnd) && !win.IsIconic(_win32.hwnd)
		
		// Handle events
		if window_is_visible && !obscured /*&& !paused*/ {
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

		if !_win32.running {break}

		if _win32.drag_drop_done {
			server.queue_files_for_scanning(&sv, _win32.drag_drop_payload[:])
			delete(_win32.drag_drop_payload)
			_win32.drag_drop_payload = nil
			_win32.drag_drop_done = false
		}

		_update_window_size()

		server.handle_events(&sv)
		client.handle_events(&ui, &sv)

		// Show frame
		{
			clear_color: [4]f32 = {0, 0, 0, 1}
			
			if _win32.need_reload_font {
				_win32.need_reload_font = false
				load_fonts(&ui, _win32.dpi_scale)
			}

			_win32.d3d.ctx->OMSetRenderTargets(1, &_win32.d3d.render_target, nil)
			_win32.d3d.ctx->ClearRenderTargetView(_win32.d3d.render_target, &clear_color)

			imgui_win32.NewFrame()
			imgui_dx11.NewFrame()
			imgui.NewFrame()
			
			// Update UI
			client.frame(&ui, &sv, prev_frame_start, frame_start)

			imgui.Render()

			draw_data := imgui.GetDrawData()
			if draw_data != nil {
				imgui_dx11.RenderDrawData(draw_data)
			}

			imgui.FontAtlas_ClearTexData(imgui.GetIO().Fonts)
			imgui.FontAtlas_ClearInputData(imgui.GetIO().Fonts)

			if ui.want_quit {
				win.PostMessageW(_win32.hwnd, win.WM_QUIT, 0, 0)
			}

			obscured = _win32.d3d.swapchain->Present(1, {}) == dxgi.STATUS_OCCLUDED
		}
	}

	win.DestroyWindow(_win32.hwnd)

	return true
}

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger()

		allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&allocator)
		defer {
			for key, value in allocator.allocation_map {
				fmt.println(key, value.location)
			}

			mem.tracking_allocator_destroy(&allocator)
		}
	}
	else {
		log_file, file_error := os.open("log.txt", os.O_WRONLY)
		if file_error != nil {
			context.logger = log.create_file_logger(log_file)
		}

		defer if file_error != nil {os.close(log_file)}

		// For -vet
		a, _ := mem.make_dynamic_array([dynamic]f32)
		fmt.println(a)
		delete(a)
	}

	run()
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> int {
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
			win.ShowWindow(hwnd, win.SW_HIDE)
			return 0
		}
		case win.WM_DPICHANGED: {
			_win32.dpi_scale = imgui_win32.GetDpiScaleForHwnd(_win32.hwnd)
			set_ui_scale(_win32.dpi_scale)
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

@(private="file")
_init_dx11 :: proc() {
	swapchain := dxgi.SWAP_CHAIN_DESC {
		BufferCount = 2,
		BufferDesc = {
			Format = .R8G8B8A8_UNORM,
			RefreshRate = {Numerator = 60, Denominator = 1},
		},
		Flags = {.ALLOW_MODE_SWITCH},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		OutputWindow = _win32.hwnd,
		SampleDesc = {
			Count = 1,
		},
		Windowed = true,
		SwapEffect = .DISCARD,
	}

	feature_levels := []dx11.FEATURE_LEVEL {
		._11_1,
		._11_0,
	}

	selected_feature_level: dx11.FEATURE_LEVEL

	win32_check(
		dx11.CreateDeviceAndSwapChain(
			nil, .HARDWARE, nil, {},
			raw_data(feature_levels), auto_cast len(feature_levels), dx11.SDK_VERSION,
			&swapchain, &_win32.d3d.swapchain, &_win32.d3d.device,
			&selected_feature_level, &_win32.d3d.ctx
		)
	)
}

@(private="file")
_clean_up_dx11 :: proc() {
	_destroy_render_target()
	if _win32.d3d.swapchain != nil {_win32.d3d.swapchain->Release()}
	if _win32.d3d.ctx != nil {_win32.d3d.ctx->Release()}
	if _win32.d3d.device != nil {_win32.d3d.device->Release()}
}

@(private="file")
_create_render_target :: proc() {
	texture: ^dx11.ITexture2D
	_win32.d3d.swapchain->GetBuffer(0, dx11.ITexture2D_UUID, cast(^rawptr) &texture)
	if texture == nil {
		_win32.d3d.render_target = nil
		return
	}
	_win32.d3d.device->CreateRenderTargetView(texture, nil, &_win32.d3d.render_target)
	texture->Release()
}

@(private="file")
_destroy_render_target :: proc() {
	if _win32.d3d.render_target != nil {
		_win32.d3d.render_target->Release()
		_win32.d3d.render_target = nil
	}
}

@(private="file")
_update_window_size :: proc() {
	if _win32.resize_height != 0 {
		_destroy_render_target()
		_win32.d3d.swapchain->ResizeBuffers(1, auto_cast _win32.resize_width, auto_cast _win32.resize_height, .UNKNOWN, {})
		_create_render_target()
		_win32.resize_width = 0
		_win32.resize_height = 0
	}
}

win32_check :: proc(hr: win.HRESULT, expr := #caller_expression(hr), loc := #caller_location) -> bool {
	if !win.SUCCEEDED(hr) {
		log.error(expr, "HRESULT", hr)
		return false
	}

	return true
}

create_imgui_texture :: proc(data: rawptr, width, height: int) -> (out: imgui.TextureID, ok: bool) {
	staging: ^dx11.ITexture2D
	texture: ^dx11.ITexture2D
	view: ^dx11.IShaderResourceView

	desc := dx11.TEXTURE2D_DESC {
		Width = auto_cast width,
		Height = auto_cast height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		Usage = .DYNAMIC,
		BindFlags = {.SHADER_RESOURCE},
		CPUAccessFlags = {.WRITE},
	}
	
	win32_check(_win32.d3d.device->CreateTexture2D(&desc, nil, &staging)) or_return
	defer staging->Release()
	
	desc.Usage = .DEFAULT
	desc.CPUAccessFlags = {}
	win32_check(_win32.d3d.device->CreateTexture2D(&desc, nil, &texture)) or_return
	defer texture->Release()

	mapped: dx11.MAPPED_SUBRESOURCE
	win32_check(_win32.d3d.ctx->Map(staging, 0, .WRITE_DISCARD, {}, &mapped)) or_return

	// If the target pitch is not the same we need to manually
	// copy each pixel
	pitch := 4 * width
	if mapped.RowPitch != u32(pitch) {
		out := cast([^]u8) mapped.pData
		pixels := cast([^]u8) data
		offset := 0

		for row in 0..<height {
			row_start := row * int(mapped.RowPitch)
			copy(out[row_start:][:mapped.RowPitch], pixels[offset:][:pitch])

			offset += pitch
		}
	}
	else {
		out := cast([^]u8) mapped.pData
		pixels := cast([^]u8) data
		size := width * height * 4

		copy(out[:size], pixels[:size])
	}

	_win32.d3d.ctx->Unmap(staging, 0)
	_win32.d3d.ctx->CopyResource(texture, staging)

	sr := dx11.SHADER_RESOURCE_VIEW_DESC {
		Format = desc.Format,
		ViewDimension = .TEXTURE2D,
		Texture2D = {
			MipLevels = 1,
		},
	}

	win32_check(_win32.d3d.device->CreateShaderResourceView(texture, &sr, &view)) or_return

	out = view
	ok = true
	return
}

destroy_imgui_texture :: proc(texture: imgui.TextureID) {
	if texture != nil {
		view := cast(^dx11.IShaderResourceView)texture
		view->Release()
	}
}

set_ui_scale :: proc(scale: f32) {
	log.info("Setting UI scale:", scale)
	style := imgui.GetStyle()
	imgui.Style_ScaleAllSizes(style, scale)
	style.WindowBorderSize = 1
	style.ChildBorderSize = 1
	style.PopupBorderSize = 1
	style.FrameBorderSize = 1
	style.TabBorderSize = 1

	_win32.need_reload_font = true
}

load_fonts :: proc(ui: ^client.Client, scale: f32) {
	imgui_dx11.InvalidateDeviceObjects()
	defer imgui_dx11.CreateDeviceObjects()

	client.load_fonts(
		ui,
		[]client.Load_Font {
			{
				path = "C:\\Windows\\Fonts\\seguisb.ttf",
				size = 16 * scale,
				languages = {.English, .Cyrillic},
			},
			{
				path = "C:\\Windows\\Fonts\\yugothb.ttc",
				size = 16 * scale,
				languages = {.Japanese},
			},
			{
				data = #load("data/FontAwesome.otf"),
				size = 11 * scale,
				languages = {.Icons},
			},
		}
	)
}

set_window_title :: proc(title: string) {
	buf_u16: [256]u16
	utf16.encode_string(buf_u16[:len(buf_u16)-1], title)
	win.SetWindowTextW(_win32.hwnd, raw_data(buf_u16[:]))
}

add_tray_icon :: proc() {
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

remove_tray_icon :: proc() {
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

import "src:util"

drag_drop_drop :: proc "c" (path: cstring) {
	context = _win32.ctx
	if _win32.drag_drop_done {return}
	else if path == nil {
		_win32.drag_drop_done = true
	}
	else {
		buf: server.Path
		util.copy_string_to_buf(buf[:], string(path))
		append(&_win32.drag_drop_payload, buf)
		log.debug(path)
	}
}
