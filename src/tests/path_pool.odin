package tests

import "core:testing"
import "core:path/filepath"
import "core:log"
import pp "src:path_pool"

@test
test_path_pool :: proc(t: ^testing.T) {
	pool: pp.Pool

	defer pp.destroy(pool)

	store_and_check :: proc(t: ^testing.T, pool: ^pp.Pool, path: string) {
		buf: [512]u8
		path_ref := pp.store(pool, path)
		str := pp.retrieve(pool^, path_ref, buf[:])
		cleaned_path := filepath.clean(path)
		defer delete(cleaned_path)

		log.debug("Input:", path, "|", "Stored:", str)
		testing.expect(t, str == cleaned_path)
	}

	store_and_check(t, &pool, "some/file")
	store_and_check(t, &pool, "some/file2")
	testing.expect(t, len(pool.dirs) == 1)
	store_and_check(t, &pool, "some\\other/file")
	log.debug(len(pool.dirs))
	testing.expect(t, len(pool.dirs) == 2)
}
