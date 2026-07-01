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
package main

import "core:sync"

PROGRAM_VERSION_STRING :: "0.5.0"
PROGRAM_NAME :: "RAT MP"
PROGRAM_ID :: "ratmp"
PROGRAM_FOLDER_NAME :: "ratmp"
PROGRAM_NAME_AND_VERSION :: PROGRAM_NAME + " | " + PROGRAM_VERSION_STRING

Global_Flag :: enum {
	VideoDeviceLost,
	Headless,
}

global_flags: bit_set[Global_Flag]

UID :: distinct u64

generate_uid :: proc() -> UID {
	@static counter: UID
	return sync.atomic_add(&counter, 1)
}

global_command_opts: struct {
	headless:          bool `usage:"Run without UI."`,
	no_media_controls: bool `usage:"Don't use system media controls."`,
	force_opengl:      bool `usage:"(Windows) Force using OpenGL if DX11 is not supported on your device."`,
	no_tray:           bool `usage:"Don't display a system tray icon."`,
	no_audio:          bool `usage:"(Debug) Disable audio output."`,
	profile_startup:   bool `args:"hidden" usage:"(Profiling) Exit after initial startup."`,
	memory_debug:      bool `usage:"(Debug) Enable memory tracking."`,
	heap_alloc_log:    bool `usage:"(Debug) Logs heap memory allocations to the console."`,
}

global_paths: struct {
	config_dir: string,
	data_dir: string,
	settings: string,
}

global_config: Config
global_config_dirty: bool

global_delta_time: f32
global_uptime: f64

