#+private
package client

import "core:strings"
import "core:mem"
import "core:time"
import "core:fmt"
import "core:hash/xxhash"
import "src:server"
import imgui "src:thirdparty/odin-imgui"
import "imx"

Track_Category_Row :: struct {
	hash: server.Track_Category_Hash,
	name: cstring,
	track_count: i32,
	duration: [12]u8,
	track_count_str: [5]u8,
	track_count_len: u8,
	duration_len: u8,
}

Track_Category_Table :: struct {
	rows: [dynamic]Track_Category_Row,
	serial: uint,
	filter_hash: u32,
}

Track_Category_Hash_And_Playlist_ID :: struct {
	hash: server.Track_Category_Hash,
	playlist_id: Playlist_ID,
}

Track_Category_Table_Result :: struct {
	sort_spec: Maybe(server.Playlist_Sort_Spec),
	select: Maybe(server.Track_Category_Hash),
	play: Maybe(server.Track_Category_Hash),
	append_to_queue: Maybe(server.Track_Category_Hash),
	add_to_auto_playlist: Maybe(Track_Category_Hash_And_Playlist_ID),
	add_to_playlist: Maybe(Track_Category_Hash_And_Playlist_ID),
	context_target: Maybe(server.Track_Category_Hash),
}

track_category_table_update :: proc(table: ^Track_Category_Table, cat: ^server.Track_Category, serial: uint, filter: string) {
	filter_hash := xxhash.XXH32(transmute([]u8) filter)

	if table.serial == serial && table.filter_hash == filter_hash {
		return
	}

	table.serial = serial
	table.filter_hash = filter_hash
	clear(&table.rows)

	entry_to_row :: proc(entry: #soa^#soa[]server.Track_Category_Entry) -> (row: Track_Category_Row) {
		row.hash = entry.hash
		row.name = entry.name_cstring
		hours, minutes, seconds := time.clock_from_seconds(auto_cast entry.duration)
		row.duration_len = auto_cast len(fmt.bprintf(row.duration[:], "%02d:%02d:%02d", hours, minutes, seconds))
		row.track_count = auto_cast len(entry.tracks)
		row.track_count_len = auto_cast len(fmt.bprint(row.track_count_str[:], row.track_count))
		return
	}

	if filter == "" {
		resize(&table.rows, len(cat.entries))

		for _, i in cat.entries {
			table.rows[i] = entry_to_row(&cat.entries[i])
		}
	}
	else {
		stack: mem.Stack
		stack_data := make([]byte, 4096)
		defer delete(stack_data)
		mem.stack_init(&stack, stack_data)
		allocator := mem.stack_allocator(&stack)

		filter_lower := strings.to_lower(filter, allocator)

		for entry, i in cat.entries {
			name_lower := strings.to_lower(entry.name, allocator)
			defer mem.stack_free(&stack, raw_data(name_lower))

			if strings.contains(name_lower, filter_lower) {
				append(&table.rows, entry_to_row(&cat.entries[i]))
			}
		}
	}
}

track_category_table_show :: proc(
	cat: ^server.Track_Category,
	table: Track_Category_Table, lib: Library, viewing_hash: server.Track_Category_Hash
) -> (result: Track_Category_Table_Result, shown: bool) {
	table_flags := imgui.TableFlags_Sortable |
		imgui.TableFlags_SortTristate |
		imgui.TableFlags_SizingStretchProp |
		imgui.TableFlags_ScrollY |
		imgui.TableFlags_RowBg |
		imgui.TableFlags_Resizable |
		imgui.TableFlags_BordersInner |
		imgui.TableFlags_Hideable |
		imgui.TableFlags_Reorderable

	imgui.BeginTable("##track_categories", 3, table_flags) or_return
	defer imgui.EndTable()

	imgui.TableSetupColumn("Name")
	imgui.TableSetupColumn("No. Tracks")
	imgui.TableSetupColumn("Duration")

	imgui.TableSetupScrollFreeze(1, 1)
	imgui.TableHeadersRow()

	if table_sort_specs := imgui.TableGetSortSpecs(); table_sort_specs != nil {
		if specs := table_sort_specs.Specs; specs != nil && table_sort_specs.SpecsDirty {
			metric: server.Playlist_Sort_Metric
			order: server.Sort_Order

			table_sort_specs.SpecsDirty = false

			switch specs.ColumnIndex {
				case 0: metric = .Name
				case 1: metric = .Length
				case 2: metric = .Duration
			}

			switch specs.SortDirection {
				case .Ascending: order = .Ascending
				case .Descending: order = .Descending
				case .None: order = .Descending
			}

			result.sort_spec = server.Playlist_Sort_Spec {
				metric = metric,
				order = order,
			}
		}
	}

	list_clipper: imgui.ListClipper
	imgui.ListClipper_Begin(&list_clipper, auto_cast len(table.rows))
	defer imgui.ListClipper_End(&list_clipper)

	for imgui.ListClipper_Step(&list_clipper) {
		for &row in table.rows[list_clipper.DisplayStart:list_clipper.DisplayEnd] {
			imgui.TableNextColumn()

			if imgui.TableSetColumnIndex(0) {
				if row.name != nil && string(row.name) != "" {
					if imgui.Selectable(row.name, row.hash == viewing_hash, {.SpanAllColumns}) {
						result.select = row.hash
					}
				}
				else {
					imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
					if imgui.Selectable("None", row.hash == viewing_hash, {.SpanAllColumns}) {
						result.select = row.hash
					}

					imgui.PopStyleColor()
				}

				if is_play_track_input_pressed() {
					result.select = row.hash
					result.play = row.hash
				}

				imgui.SetItemTooltip("%d tracks", i32(row.track_count))

				if imgui.BeginDragDropSource() {
					entry_index, have_entry := server.track_category_find_entry_index(cat, row.hash)
					if have_entry {
						set_track_drag_drop_payload(cat.entries[entry_index].tracks[:])
					}
					imgui.EndDragDropSource()
				}

				if imgui.BeginPopupContextItem() {
					result.context_target = row.hash
					if imgui.MenuItem("Play") {result.play = row.hash}
					if imgui.MenuItem("Append to queue") {result.append_to_queue = row.hash}
					if imgui.BeginMenu("Automatically add to playlist") {
						for playlist in lib.playlists {
							if playlist.auto_build_params == nil {continue}
							if imgui.MenuItem(playlist.name_cstring) {
								result.add_to_auto_playlist = Track_Category_Hash_And_Playlist_ID{hash = row.hash, playlist_id = playlist.id}
							}
						}
						imgui.EndMenu()
					}
					if imgui.BeginMenu("Append to playlist") {
						for playlist in lib.playlists {
							if playlist.auto_build_params != nil {continue}
							if imgui.MenuItem(playlist.name_cstring) {
								result.add_to_playlist = Track_Category_Hash_And_Playlist_ID{hash = row.hash, playlist_id = playlist.id}
							}
						}
						imgui.EndMenu()
					}
					imgui.EndPopup()
				}
			}

			if imgui.TableSetColumnIndex(1) {
				imx.text_unformatted(string(row.track_count_str[:row.track_count_len]))
			}

			if imgui.TableSetColumnIndex(2) {
				imx.text_unformatted(string(row.duration[:row.duration_len]))
			}
		}
	}

	shown = true
	return
}

track_category_table_free :: proc(table: ^Track_Category_Table) {
	delete(table.rows)
	table.rows = nil
	table.serial = 0
	table.filter_hash = 0
}
