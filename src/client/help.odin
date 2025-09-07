#+private
package client

import "core:time"

import imgui "src:thirdparty/odin-imgui"

import "src:client/imx"
import "src:licenses"
import "src:build"

@(private="file")
ABOUT_TEXT :: `
RAT MP - A cross-platform, extensible music player
`

_show_license_window :: proc() {
	ratmp := licenses.get_license()
	tp := licenses.get_third_party_licenses()

	show_license :: proc(l: licenses.License) {
		imx.separator_text(l.name)
		imx.text_unformatted(l.ownage)
		imx.hyperlink(l.url)
	}

	show_license(ratmp)

	imgui.Separator()

	for l in tp {
		show_license(l)
	}
}

_show_about_window :: proc() {
	compile_time_buf: [256]u8
	compile_time := time.unix(0, ODIN_COMPILE_TIMESTAMP)
	compile_time_string := time.to_string_yyyy_mm_dd(compile_time, compile_time_buf[:])

	imx.text_unformatted("RAT MP - A cross-platform, extensible music player")
	imx.text(64, "Version:", build.PROGRAM_VERSION)
	imx.text(64, "Compile date (yyyy/mm/dd):", compile_time_string)
	imx.text(64, "Arch:", ODIN_ARCH)
	imx.text(64, "Optimization:", ODIN_OPTIMIZATION_MODE)
	imx.text(64, "Odin compiler version:", ODIN_VERSION)
}
