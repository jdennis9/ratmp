package sys_main

import "base:runtime"

import "core:thread"
import "core:log"
import "core:path/filepath"
import "core:os/os2"

import "vendor:glfw"
import stbi "vendor:stb/image"

import imgui_glfw "src:thirdparty/odin-imgui/imgui_impl_glfw"
import imgui_gl "src:thirdparty/odin-imgui/imgui_impl_opengl3"

import "src:bindings/linux_misc"

import "src:build"
import "src:server"
import "src:client"
import "src:sys"

ICON_PNG_DATA := #load("../../resources/ratmp.png")

@private
_linux: struct {
	ctx: runtime.Context,
	window: glfw.WindowHandle,
	window_visible: bool,
	running: bool,
	sv: ^server.Server,
	cl: ^client.Client,
	want_exit: bool,

	minimize_to_tray_dialog: sys.Dialog_State,
}

@private
_window_close_callback :: proc "c" (window: glfw.WindowHandle) {
	context = _linux.ctx

	switch _linux.cl.settings.close_policy {
		case .AlwaysAsk: {
			sys.async_dialog_open(&_linux.minimize_to_tray_dialog, .YesNo, "Choose action", "Would you like to minimize RAT MP to the system tray?")
		}
		case .Exit: {
			_linux.running = false
		}
		case .MinimizeToTray: {
			show_window(false)
		}
	}
}

@private
_systray_event_handler :: proc "c" (event: linux_misc.Systray_Event) {
	switch event {
		case .Exit: _linux.running = false
		case .Show: show_window(true)
	}
}

init :: proc(sv: ^server.Server, cl: ^client.Client) -> (data_dir, config_dir: string, ok: bool) {
	_linux.sv = sv
	_linux.cl = cl
	_linux.ctx = context
	linux_misc.init()
	linux_misc.systray_init(_systray_event_handler)


	when ODIN_DEBUG {
		data_dir = "."
		config_dir = "."
	}
	else {
		home := os2.get_env_alloc("HOME", context.allocator)
		defer delete(home)

		if home != "" {
			data_dir = filepath.join({home, ".local/share/ratmp"})
			config_dir = filepath.join({home, ".config/ratmp"})

			if !os2.exists(data_dir) {os2.mkdir(data_dir)}
			if !os2.exists(config_dir) {os2.mkdir(config_dir)}
		}
		else {
			return
		}
	}

	ok = true
	return
}

create_window :: proc() -> bool {
	glfw.Init()

	_linux.window = glfw.CreateWindow(1600, 900, build.PROGRAM_NAME_AND_VERSION, nil, nil)
	if _linux.window == nil {return false}
	glfw.MakeContextCurrent(_linux.window)

	load_icon :: proc() -> bool {
		w, h: i32

		icon_pixels := stbi.load_from_memory(
			raw_data(ICON_PNG_DATA), auto_cast len(ICON_PNG_DATA),
			&w, &h, nil, 4
		)

		if icon_pixels == nil {return false}
		defer stbi.image_free(icon_pixels)

		icon_image: glfw.Image = {
			pixels = icon_pixels
		}

		glfw.SetWindowIcon(_linux.window, {icon_image})

		log.debug("Loaded window icon")

		return true
	}

	load_icon()

	sys._gl_init(_linux.window)

	glfw.SetWindowCloseCallback(_linux.window, _window_close_callback)

	imgui_glfw.InitForOpenGL(_linux.window, true)
	imgui_gl.Init()

	_linux.running = true

	return true
}

present :: proc() {
	if _linux.window_visible {
		glfw.SwapBuffers(_linux.window)
	}
}

shutdown :: proc() {
	glfw.DestroyWindow(_linux.window)
	imgui_gl.Shutdown()
	imgui_glfw.Shutdown()
}

new_frame :: proc() {
	sys._gl_clear_buffer()

	imgui_glfw.NewFrame()
	imgui_gl.NewFrame()
}

// Return false to terminate program
handle_events :: proc() -> bool {
	if _linux.window_visible {glfw.PollEvents()}
	else {glfw.WaitEventsTimeout(0.05)}
	linux_misc.update()

	if result, have_result := sys.async_dialog_get_result(&_linux.minimize_to_tray_dialog); have_result {
		if result {
			show_window(false)
		}
		else {
			_linux.running = false
		}

		sys.async_dialog_destroy(&_linux.minimize_to_tray_dialog)
	}

	return _linux.running
}

show_window :: proc "contextless" (show: bool) {
	_linux.window_visible = show

	if show {
		glfw.ShowWindow(_linux.window)
	}
	else {
		glfw.HideWindow(_linux.window)
	}
}

post_empty_event :: proc() {
	glfw.PostEmptyEvent()
}

set_window_title :: proc(title: string) {
	buf: [256]u8
	copy(buf[:255], title)
	glfw.SetWindowTitle(_linux.window, cstring(&buf[0]))
}
