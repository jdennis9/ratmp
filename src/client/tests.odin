package client

import "core:testing"

@test
test_selection :: proc(t: ^testing.T) {
	sel: _Selection
	defer delete(sel.tracks)

	check_duplicates :: proc(t: ^testing.T, tracks: []Track_ID) {
		for i in 0..<len(tracks) {
			for j in 0..<len(tracks) {
				if i != j {
					testing.expect(t, tracks[i] != tracks[j])
				}
			}
		}
	}

	tracks := []Track_ID {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}

	_selection_add(&sel, {}, 1)
	testing.expect(t, len(sel.tracks) == 1)

	_selection_add(&sel, {1, 1}, 1)
	testing.expect(t, len(sel.tracks) == 1)

	_selection_clear(&sel)

	_selection_extend(&sel, {}, tracks, 3)
	testing.expect(t, len(sel.tracks) == 3)
	check_duplicates(t, sel.tracks[:])

	_selection_extend(&sel, {}, tracks, 6)
	check_duplicates(t, sel.tracks[:])

	_selection_extend(&sel, {}, tracks, 1)
	check_duplicates(t, sel.tracks[:])

	_selection_clear(&sel)
	_selection_add(&sel, {}, 11)
	_selection_extend(&sel, {}, tracks, 9)
	check_duplicates(t, sel.tracks[:])
	testing.expect(t, len(sel.tracks) == 3)
}
