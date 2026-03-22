package main

Global_Flag :: enum {
	VideoDeviceLost,
	Headless,
}

global_flags: bit_set[Global_Flag]

UID :: distinct u64

generate_uid :: proc() -> UID {
	@static counter: UID
	counter += 1
	return counter
}
