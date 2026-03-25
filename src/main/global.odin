package main

PROGRAM_VERSION_STRING :: "0.5.0"
PROGRAM_NAME :: "RAT MP"
PROGRAM_ID :: "ratmp"
PROGRAM_NAME_AND_VERSION :: PROGRAM_NAME + " | " + PROGRAM_VERSION_STRING

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
