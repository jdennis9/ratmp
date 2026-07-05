package shared

import "core:mem"

track_allocator :: proc(allocator: mem.Allocator, tracker: ^mem.Tracking_Allocator) -> mem.Allocator {
	mem.tracking_allocator_init(tracker, allocator)
	return mem.tracking_allocator(tracker)
}
