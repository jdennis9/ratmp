package main

import "core:encoding/json"
import "core:mem"
import "core:os"
import "core:log"

Custom_Error :: enum {
	InvalidName,
	InvalidInput,
	NotFound,
	// Error happening in third-party library
	ThirdParty,
}

Error :: union {
	bool,
	os.Error,
	mem.Allocator_Error,
	json.Unmarshal_Error,
	json.Marshal_Error,
	Custom_Error,
}

check_error_0 :: proc(r: $R) -> bool {
	if r != nil {
		log.error(r)
		return false
	}
	return true
}

check_error_1 :: proc(p1: $T, r: $R) -> (r1: T, ok: bool) {
	if r != nil {
		log.error(r)
		return
	}
	r1 = p1
	ok = true
	return
}

check_error_2 :: proc(p1: $T, p2: $T2, r: $R) -> (r1: T, r2: T2, ok: bool) {
	if r != nil {
		log.error(r)
		return
	}
	r1 = p1
	r2 = p2
	ok = true
	return
}

check_error :: proc {
	check_error_0,
	check_error_1,
	check_error_2,
}
