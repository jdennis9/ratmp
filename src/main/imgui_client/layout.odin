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
package client

import "core:sort"
import imgui "src:thirdparty/odin-imgui"
import "core:strings"
import "src:main/shared"
import "core:mem"
import "core:os"
import "core:path/filepath"

_want_load_layout: cstring
_layouts: [dynamic; 64]string

_sort_layouts :: proc() {
	iface := sort.Interface {
		len = proc(it: sort.Interface) -> int {return len(_layouts)},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			return strings.compare(_layouts[a], _layouts[b]) < 0
		},
		swap = proc(it: sort.Interface, a, b: int) {
			_layouts[a], _layouts[b] = _layouts[b], _layouts[a]
		}
	}
}

@private
get_layouts_path :: proc(allocator: mem.Allocator) -> (string, mem.Allocator_Error) #optional_allocator_error {
	return filepath.join({get_config_path(), "layouts"}, allocator)
}

@private
get_layout_filename :: proc(
	layout_name: string, allocator: mem.Allocator, temp_allocator: mem.Allocator
) -> (path: string, error: mem.Allocator_Error) #optional_allocator_error {
	fname := strings.concatenate({layout_name, ".ini"}, temp_allocator)
	return filepath.join({get_layouts_path(temp_allocator), fname}, allocator)
}

@private
init_layouts :: proc() -> shared.Error {
	need_add_default_layouts: bool

	path := get_layouts_path(context.allocator) or_return
	defer delete(path)

	need_add_default_layouts |= !os.exists(path)

	shared.ensure_dir(path)

	add_defaults_blk: if need_add_default_layouts {
		filename := get_layout_filename("Default", context.allocator, get_frame_allocator())
		file := os.create(filename) or_break add_defaults_blk
		defer os.close(file)
		os.write(file, transmute([]byte) string(_DEFAULT_LAYOUT_INI))
	}

	refresh_layouts()

	return nil
}

@private
update_layout :: proc() {
	// Load layout
	if _want_load_layout != nil {
		imgui.LoadIniSettingsFromMemory(_want_load_layout)
		delete(_want_load_layout)
		_want_load_layout = nil
	}
}


@private
refresh_layouts :: proc() -> shared.Error {
	path := get_layouts_path(context.allocator) or_return
	defer delete(path)

	// Clear existing
	for l in _layouts do delete(l)
	clear(&_layouts)

	files := os.read_all_directory_by_path(path, context.allocator) or_return
	defer os.file_info_slice_delete(files, context.allocator)

	for file in files {
		if file.type != .Regular do continue
		name := filepath.stem(filepath.base(file.fullpath))

		append(&_layouts, strings.clone(name))
	}

	_sort_layouts()

	return nil
}

@private
save_layout :: proc(name: string) -> shared.Error {
	temp_allocator := get_frame_allocator()
	frame_allocator_guard()

	path := get_layout_filename(name, context.allocator, temp_allocator) or_return
	defer delete(path)

	imgui.SaveIniSettingsToDisk(strings.clone_to_cstring(path, temp_allocator))

	for l in _layouts do if l == name do return nil

	append(&_layouts, name)

	_sort_layouts()

	return nil
}

@private
load_layout :: proc(name: string) -> shared.Error {
	temp_allocator := get_frame_allocator()
	frame_allocator_guard()

	path := get_layout_filename(name, temp_allocator, temp_allocator) or_return
	str := os.read_entire_file_from_path(path, temp_allocator) or_return
	_want_load_layout = strings.clone_to_cstring(string(str))

	return nil
}

@private
get_layouts :: proc() -> []string {
	return _layouts[:]
}


_DEFAULT_LAYOUT_INI :: `
[Window][WindowOverViewport_11111111]
Pos=0,20
Size=1904,958
Collapsed=0

[Window][Debug##Default]
Pos=60,60
Size=400,400
Collapsed=0

[Window][_library]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,0

[Window][_queue]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,5

[Window][_theme_editor]
Pos=0,54
Size=1519,687
Collapsed=0
DockId=0x00000005,5

[Window][_metadata]
Pos=1483,410
Size=421,568
Collapsed=0
DockId=0x0000000B,0

[Window][_cover_art]
Pos=1483,20
Size=421,388
Collapsed=0
DockId=0x00000007,0

[Window][_artists]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,4

[Window][_genres]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,3

[Window][_albums]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,2

[Window][_settings]
Pos=586,302
Size=564,480
Collapsed=0

[Window][_spectrum]
Pos=0,743
Size=1481,235
Collapsed=0
DockId=0x00000006,0

[Window][_wavebar]
Pos=0,20
Size=1481,32
Collapsed=0
DockId=0x00000001,0

[Window][_folders]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,1

[Window][_playlists]
Pos=0,54
Size=1481,687
Collapsed=0
DockId=0x00000005,6

[Window][_license]
Pos=574,292
Size=555,638
Collapsed=0

[Window][_about]
Pos=833,209
Size=278,186
Collapsed=0

[Window][Metadata Scan]
Pos=60,60
Size=300,100
Collapsed=0

[Window][_missing_tracks]
Pos=734,54
Size=785,687
Collapsed=0
DockId=0x00000005,1

[Window][_oscilloscope]
Pos=1521,729
Size=383,249
Collapsed=0
DockId=0x0000000C,0

[Table][0x3FFD90F9,3]
Column 0  Weight=1.5345
Column 1  Weight=0.5345
Column 2  Weight=0.9310

[Table][0x3EDCE146,3]
Column 0  Weight=0.6316 Sort=0v
Column 1  Weight=1.2919
Column 2  Weight=1.0766

[Table][0xB0310ADC,4]
Column 0  Weight=2.3374 Sort=0v
Column 1  Weight=0.4401
Column 2  Weight=0.5917
Column 3  Weight=0.6308

[Table][0x94E7B2E7,4]
Column 0  Weight=0.4583 Sort=0v
Column 1  Weight=0.9375
Column 2  Weight=1.2604
Column 3  Weight=1.3438

[Table][0x9B47C04B,4]
Column 0  Weight=1.1608 Sort=0v
Column 1  Weight=0.7516
Column 2  Weight=1.0104
Column 3  Weight=1.0772

[Table][0x6F975913,9]
Column 1  Sort=0v

[Table][0xECC54ACF,9]
Column 1  Sort=0v

[Table][0x7AC910FA,9]
Column 1  Sort=0v

[Table][0xACEA18C9,2]
Column 0  Weight=1.1324
Column 1  Weight=1.2009

[Docking][Data]
DockSpace       ID=0x08BD597D Window=0x1BBC0F80 Pos=0,20 Size=1904,958 Split=X Selected=0x01F4E0DB
  DockNode      ID=0x00000003 Parent=0x08BD597D SizeRef=1481,958 Split=Y
    DockNode    ID=0x00000001 Parent=0x00000003 SizeRef=1904,32 HiddenTabBar=1 Selected=0x2BE05361
    DockNode    ID=0x00000002 Parent=0x00000003 SizeRef=1904,924 Split=Y Selected=0x34E066FD
      DockNode  ID=0x00000005 Parent=0x00000002 SizeRef=1519,687 CentralNode=1 Selected=0x34E066FD
      DockNode  ID=0x00000006 Parent=0x00000002 SizeRef=1519,235 Selected=0x8C0843EF
  DockNode      ID=0x00000004 Parent=0x08BD597D SizeRef=421,958 Split=Y Selected=0xF4DC7244
    DockNode    ID=0x00000007 Parent=0x00000004 SizeRef=383,388 Selected=0xF4DC7244
    DockNode    ID=0x00000008 Parent=0x00000004 SizeRef=383,568 Split=Y Selected=0xE1D1E3C9
      DockNode  ID=0x0000000B Parent=0x00000008 SizeRef=383,317 Selected=0xE1D1E3C9
      DockNode  ID=0x0000000C Parent=0x00000008 SizeRef=383,249 Selected=0x21B107BD

[RATMP][_library]
_Open=true
[RATMP][_queue]
_Open=true
[RATMP][_theme_editor]
_Open=false
[RATMP][_metadata]
_Open=true
[RATMP][_cover_art]
_Open=true
[RATMP][_artists]
_Open=true
[RATMP][_genres]
_Open=true
[RATMP][_albums]
_Open=true
[RATMP][_settings]
_Open=false
[RATMP][_spectrum]
_Open=true
Mode=Histogram
WindowFunc=Blackman
BandCount=160
[RATMP][_wavebar]
_Open=true
ApplyReplayGain=false
ColorMode=Gradient
PeakMul=1
[RATMP][_folders]
_Open=true
[RATMP][_playlists]
_Open=true
[RATMP][_license]
_Open=false
[RATMP][_about]
_Open=false
[RATMP][_missing_tracks]
_Open=false
[RATMP][_oscilloscope]
_Open=false
`

_MINIMAL_LAYOUT_INIT :: `
`

_SPECTRUM_FOCUS_LAYOUT_INIT :: `
`
