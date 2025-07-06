package server

import "core:slice"
import "core:path/filepath"
import "core:log"
import "core:os/os2"

import "src:path_pool"
import "src:util"

Playlist_List :: struct {
	serial: uint,
	list_ids: [dynamic]Playlist_ID,
	lists: [dynamic]Playlist,
	base_id: u32,
}

playlist_list_join_metadata :: proc(cat: ^Playlist_List, library: Library, component: Metadata_Component) {
	playlist_list_destroy(cat)

	cat.base_id = auto_cast component
	cat.serial += 1

	for md, track_index in library.track_metadata {
		value := md.values[component].(string) or_else ""
		hash := library_hash_string(value)		
		dst_id := Playlist_ID{serial=cat.base_id, pool=hash}

		if list_index, list_exists := slice.linear_search(cat.list_ids[:], dst_id); list_exists {
			playlist_add_track(&cat.lists[list_index], library.track_ids[track_index], md)
			continue
		}

		new_list := playlist_list_add_new(cat, value, dst_id) or_continue
		playlist_add_track(new_list, library.track_ids[track_index], md)
		new_list.serial = library.serial
	}
}

playlist_list_join_folders :: proc(cat: ^Playlist_List, library: Library) {
	playlist_list_destroy(cat)

	cat.base_id = auto_cast len(Metadata_Component)
	cat.serial += 1

	for path_ref, track_index in library.track_paths {
		path_buf: [512]u8
		md := library.track_metadata[track_index]

		path := path_pool.retrieve(library.path_allocator, path_ref, path_buf[:])
		folder_full_path := filepath.dir(path); defer delete(folder_full_path)
		folder := filepath.base(folder_full_path)
		folder_hash := library_hash_string(folder)

		dst_id := Playlist_ID{serial=cat.base_id, pool=folder_hash}

		if list_index, list_exists := slice.linear_search(cat.list_ids[:], dst_id); list_exists {
			playlist_add_track(&cat.lists[list_index], library.track_ids[track_index], md)
			continue
		}

		new_list := playlist_list_add_new(cat, folder, dst_id) or_continue
		playlist_add_track(new_list, library.track_ids[track_index], md)
	}
}

playlist_list_sort :: proc(cat: ^Playlist_List, spec: Playlist_Sort_Spec) {
	sort_playlists(cat.lists[:], spec)
	for list, index in cat.lists {
		cat.list_ids[index] = list.id
	}
	cat.serial += 1
}

playlist_list_add_new :: proc(list: ^Playlist_List, name: string, id: Playlist_ID) -> (playlist: ^Playlist, error: Error) {
	new_playlist: Playlist
	
	defer if error != .None {log.warn(error)}
	
	for p in list.lists {
		if string(p.name) == name {
			return nil, .NameExists
		}
	}
	
	playlist_init(&new_playlist, name, id)
	index := playlist_list_add(list, new_playlist)
	list.serial += 1
	return &list.lists[index], .None
}

playlist_list_add :: proc(list: ^Playlist_List, playlist: Playlist) -> int {
	index := len(list.lists)
	append(&list.list_ids, playlist.id)
	append(&list.lists, playlist)
	list.serial += 1
	return index
}

playlist_list_name_exists :: proc(list: ^Playlist_List, name: string) -> bool {
	for p in list.lists {
		if string(p.name) == name {return true}
	}
	return false
}

playlist_list_remove :: proc(list: ^Playlist_List, id: Playlist_ID) -> bool {
	index := slice.linear_search(list.list_ids[:], id) or_return
	playlist := &list.lists[index]
	if playlist.src_path != "" {
		os2.remove(playlist.src_path)
	}
	playlist_destroy(playlist)
	ordered_remove(&list.list_ids, index)
	ordered_remove(&list.lists, index)
	list.serial += 1
	return true
}

playlist_list_get :: proc(list: Playlist_List, id: Playlist_ID) -> (playlist: ^Playlist, found: bool) {
	index := slice.linear_search(list.list_ids[:], id) or_return
	return &list.lists[index], true
}

playlist_list_destroy :: proc(cat: ^Playlist_List) {
	for list in cat.lists {
		delete(list.tracks)
		delete(list.name)
	}
	delete(cat.lists)
	delete(cat.list_ids)
	cat.lists = nil
	cat.list_ids = nil
}

filter_playlists :: proc(list: ^Playlist_List, filter: string, output: ^[dynamic]Playlist_ID) {
	filter_rune_buf: [256]rune
	filter_runes := util.decode_utf8_to_runes(filter_rune_buf[:], filter)

	for &playlist in list.lists {
		if _filter_track_string(string(playlist.name), filter_runes) {
			append(output, playlist.id)
		}
	}
}
