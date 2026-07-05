package shared

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:time"

@(deferred_out=_TIMED_SCOPE_EXIT)
TIME_SCOPE :: proc(
	name_args: ..any, sep := " ", loc := #caller_location
) -> (string, time.Tick, runtime.Source_Code_Location) {
	name := fmt.aprint(..name_args, sep=sep, allocator=context.allocator)
	start := time.tick_now()
	return name, start, loc
}

@(private="file")
_TIMED_SCOPE_EXIT :: proc(name: string, start: time.Tick, loc: runtime.Source_Code_Location) {
	duration := time.tick_since(start)
	log.debugf("[TIMER] %s: %gms", name, time.duration_milliseconds(duration), location = loc)
	delete(name)
}

