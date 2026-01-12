package global

Run_Flag :: enum {
	SafeMode,
}

run_flags: bit_set[Run_Flag]
uptime: f64
