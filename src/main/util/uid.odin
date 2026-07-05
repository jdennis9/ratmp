package util

import "core:sync"

UID :: distinct u64

generate_uid :: proc() -> UID {
	@static counter: UID
	return sync.atomic_add(&counter, 1)
}
