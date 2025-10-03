#+private
package client

import "core:strings"
import "core:sort"
import "core:log"
import "core:hash/xxhash"
import "core:fmt"
import "base:runtime"
import sa "core:container/small_array"

import imgui "src:thirdparty/odin-imgui"

Window_Archetype_ID :: distinct u32

Window_Archetype_Flag :: enum {
	MultiInstance,
	NoInitialInstance,
	DefaultShow,
}

Window_Archetype_Flags :: bit_set[Window_Archetype_Flag]

Window_Base :: struct {
	archetype: Window_Archetype_ID,
	arg: uintptr,
	instance: u32,
	want_bring_to_front: bool,
	open: bool,
}

Window_Archetype :: struct {
	title, internal_name: cstring,
	flags: Window_Archetype_Flags,
	instance_flags: Window_Flags,
	instances: [4]^Window_Base,

	configure: proc(self: ^Window_Base, key: string, value: string),
	save_config: proc(self: ^Window_Base, text_buf: ^imgui.TextBuffer),
	make_instance: proc(allocator: runtime.Allocator) -> ^Window_Base,
	show: proc(self: ^Window_Base, cl: ^Client, sv: ^Server),
	// Called every frame where the window isn't visible
	hide: proc(self: ^Window_Base, cl: ^Client, sv: ^Server),
}

Window_Manager :: struct {
	archetypes: map[Window_Archetype_ID]Window_Archetype,
}

get_window_archetype_id :: proc(name: string) -> Window_Archetype_ID {
	return auto_cast xxhash.XXH32(transmute([]u8)name)
}

add_window_archetype :: proc(cl: ^Client, archetype: Window_Archetype) -> Window_Archetype_ID {
	id := get_window_archetype_id(string(archetype.internal_name))
	cl.window_archetypes[id] = archetype

	if .NoInitialInstance not_in archetype.flags {
		add_window_instance_direct(cl, &cl.window_archetypes[id])
	}

	{
		iface: sort.Interface

		clear(&cl.sorted_window_archetypes)
		for key, _ in cl.window_archetypes {append(&cl.sorted_window_archetypes, key)}

		less_proc :: proc(iface: sort.Interface, a, b: int) -> bool {
			cl := cast(^Client) iface.collection
			A := cl.window_archetypes[cl.sorted_window_archetypes[a]]
			B := cl.window_archetypes[cl.sorted_window_archetypes[b]]

			return strings.compare(string(A.title), string(B.title)) < 0
		}

		swap_proc :: proc(iface: sort.Interface, a, b: int) {
			cl := cast(^Client) iface.collection
			temp := cl.sorted_window_archetypes[a]
			cl.sorted_window_archetypes[a] = cl.sorted_window_archetypes[b]
			cl.sorted_window_archetypes[b] = temp
		}

		len_proc :: proc(iface: sort.Interface) -> int {
			return len((cast(^Client) iface.collection).sorted_window_archetypes)
		}

		iface.collection = cl
		iface.less = less_proc
		iface.swap = swap_proc
		iface.len = len_proc

		sort.sort(iface)
	}

	return id
}

add_window_instance_direct :: proc(
	cl: ^Client, archetype: ^Window_Archetype, want_index := -1
) -> (instance: ^Window_Base, ok: bool) {
	if want_index >= len(archetype.instances) {return}

	index := want_index
	if index == -1 {
		for ptr, i in archetype.instances {
			if ptr == nil {
				index = i
				break
			}
		}
	}
	if index == -1 {return}
	
	if archetype.instances[index] == nil {
		log.debug("New", archetype.title, "window with instance number", index)
		instance = archetype.make_instance(context.allocator)
		archetype.instances[index] = instance
		instance.instance = auto_cast index
	}
	else {
		instance = archetype.instances[index]
	}

	instance.archetype = get_window_archetype_id(string(archetype.internal_name))
	instance.open = .DefaultShow in archetype.flags
	ok = true
	return
}

add_window_instance_indirect :: proc(
	cl: ^Client, id: Window_Archetype_ID, want_index := -1
) -> (instance: ^Window_Base, ok: bool) {
	arch := (&cl.window_archetypes[id]) or_return
	return add_window_instance_direct(cl, arch, want_index)
}

add_window_instance_from_name :: proc(
	cl: ^Client, name: string, want_index := -1
) -> (^Window_Base, bool) {
	return add_window_instance_indirect(cl, get_window_archetype_id(name), want_index)
}

add_window_instance :: proc {
	add_window_instance_direct,
	add_window_instance_indirect,
	add_window_instance_from_name,
}

show_all_windows :: proc(cl: ^Client, sv: ^Server) {
	for id, &archetype in cl.window_archetypes {
		for instance in archetype.instances {
			if instance == nil {continue}
			show_window_instance(&archetype, instance, cl, sv)
		}
	}
}

show_window_selector :: proc(cl: ^Client) -> (window: ^Window_Base) {
	for archetype_id in cl.sorted_window_archetypes {
		at := cl.window_archetypes[archetype_id] or_continue
		for inst, i in at.instances {
			name_buf: [64]u8
			title: cstring

			if i != 0 {
				title = cstring(&name_buf[0])
				fmt.bprintf(name_buf[:len(name_buf)-1], "%s (%d)", at.title, i)
			}
			else {
				title = at.title
			}

			if inst != nil && imgui.MenuItem(title) {
				window = inst
			}
		}
	}

	return
}

show_window_instance :: proc(arch: ^Window_Archetype, window: ^Window_Base, cl: ^Client, sv: ^Server) -> (shown: bool) {
	name_buf: [512]u8
	window_flags: imgui.WindowFlags = {}
	show_menu := imgui.IsKeyDown(.ImGuiMod_Alt) && (.MultiInstance in arch.flags)

	imgui.PushIDInt(auto_cast window.instance)
	defer imgui.PopID()

	defer if !shown && arch.hide != nil {
		arch.hide(window, cl, sv)
	}

	if window.instance == 0 {
		fmt.bprint(name_buf[:511], arch.title, "###", arch.internal_name, "")
	}
	else {
		fmt.bprintf(name_buf[:511], "%s (%d)###%s@d",
			arch.title, window.instance, arch.internal_name, window.instance
		)
	}

	if show_menu {
		window_flags |= {.MenuBar}
	}

	if window.want_bring_to_front {
		window.open = true
		window.want_bring_to_front = false
		imgui.SetNextWindowFocus()
	}
	else if !window.open {return}

	if !imgui.Begin(cstring(&name_buf[0]), &window.open, window_flags) {
		imgui.End()
		return
	}

	if show_menu && imgui.BeginMenuBar() {
		if imgui.MenuItem("Create new instance") {
			child, _ := add_window_instance(cl, arch)
			if child != nil {child.open = true}
		}
		imgui.EndMenuBar()
	}

	shown = true
	arch.show(window, cl, sv)
	imgui.End()

	return
}


bring_window_to_front :: proc(cl: ^Client, archetype_name: string, instance := 0) -> (state: ^Window_Base, ok: bool) {
	state = add_window_instance_from_name(cl, archetype_name, instance) or_return
	state.want_bring_to_front = true
	state.open = true
	ok = true
	return
}
