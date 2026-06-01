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

