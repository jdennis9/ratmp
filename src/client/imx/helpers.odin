package imgui_extensions

import "core:fmt"

import imgui "src:thirdparty/odin-imgui"

text_unformatted :: proc(str: string) {
	n := len(str)
	if n == 0 {return}
	p := transmute([]u8) str
	end := &((raw_data(p))[len(p)])
	imgui.TextUnformatted(cstring(raw_data(p)), cstring(end))
}

text :: proc($MAX_CHARS: uint, args: ..any, sep := " ") {
	buf: [MAX_CHARS]u8 = ---
	formatted := fmt.bprint(buf[:], ..args, sep=sep)
	text_unformatted(formatted)
}

textf :: proc($MAX_CHARS: uint, format: string, args: ..any) {
	buf: [MAX_CHARS]u8 = ---
	formatted := fmt.bprintf(buf[:], format, ..args)
	text_unformatted(formatted)
}


begin_status_bar :: proc() -> bool {
	window_flags := imgui.WindowFlags{
		.NoScrollbar, 
		.NoSavedSettings, 
		.MenuBar,
	}

	imgui.BeginViewportSideBar(
		"##status_bar",
		imgui.GetMainViewport(),
		.Down,
		imgui.GetFrameHeight(),
		window_flags,
	) or_return

	return imgui.BeginMenuBar()
}

end_status_bar :: proc() {
	imgui.EndMenuBar()
	imgui.End()
}

