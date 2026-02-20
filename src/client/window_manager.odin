/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
#+private
package client

import "core:strings"
import "core:sort"
import "core:log"
import "core:hash/xxhash"
import "core:fmt"
import "base:runtime"

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
	imgui_flags: imgui.WindowFlags,
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
	hide: proc(self: ^Window_Base),
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
		add_window_instance_direct(&cl.window_archetypes[id])
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
	archetype: ^Window_Archetype, want_index := -1
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
	return add_window_instance_direct(arch, want_index)
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

remove_window_instance :: proc(archetype: ^Window_Archetype, instance: int) {
	window := archetype.instances[instance]
	if window == nil {return}
	if archetype.hide != nil {archetype.hide(window)}
	free(window)
	archetype.instances[instance] = nil
}

show_all_windows :: proc(cl: ^Client, sv: ^Server) {
	for _, &archetype in cl.window_archetypes {
		for instance in archetype.instances {
			if instance == nil {continue}
			show_window_instance(&archetype, instance, cl, sv)
		}
	}
}

show_window_selector :: proc(cl: ^Client) -> (window: ^Window_Base) {
	for archetype_id in cl.sorted_window_archetypes {
		have_instance: bool

		at := (&cl.window_archetypes[archetype_id]) or_continue

		for inst in at.instances {
			if inst != nil {
				have_instance = true
				break
			}
		}

		if !have_instance && imgui.MenuItem(at.title) {
			window = add_window_instance(at) or_else nil
		}

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
	window_flags: imgui.WindowFlags = window.imgui_flags
	show_menu := imgui.IsKeyDown(.ImGuiMod_Alt) && 
		(.MultiInstance in arch.flags || .NoInitialInstance in arch.flags)

	imgui.PushIDInt(auto_cast window.instance)
	defer imgui.PopID()

	defer if !shown && arch.hide != nil {
		arch.hide(window)
	}

	if window.instance == 0 {
		fmt.bprint(name_buf[:511], arch.title, "###", arch.internal_name, "")
	}
	else {
		fmt.bprintf(name_buf[:511], "%s (%d)###%s@%d",
			arch.title, window.instance, arch.internal_name, window.instance
		)
	}

	if show_menu do window_flags |= {.MenuBar}

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
	defer imgui.End()

	if show_menu && imgui.BeginMenuBar() {
		defer imgui.EndMenuBar()

		if .MultiInstance in arch.flags && imgui.MenuItem("Create new instance") {
			child, _ := add_window_instance(arch)
			if child != nil {child.open = true}
		}
		if .NoInitialInstance in arch.flags && imgui.MenuItem("Delete instance") {
			remove_window_instance(arch, auto_cast window.instance)
			return
		}
	}

	shown = true
	arch.show(window, cl, sv)

	return
}

bring_window_to_front :: proc(cl: ^Client, archetype_name: string, instance := 0) -> (state: ^Window_Base, ok: bool) {
	state = add_window_instance_from_name(cl, archetype_name, instance) or_return
	state.want_bring_to_front = true
	state.open = true
	ok = true
	return
}

show_window_manager_window :: proc(cl: ^Client) {
	for id in cl.sorted_window_archetypes {
		at := (&cl.window_archetypes[id]) or_continue

		if imgui.TreeNode(at.title) {
			defer imgui.TreePop()

			want_remove_instance := -1

			imgui.BeginDisabled(.MultiInstance not_in at.flags)
			if imgui.Button("Add instance") {
				new_instance, _ := add_window_instance(at)
				if new_instance != nil {new_instance.open = true}
			}
			imgui.EndDisabled()
			imgui.SameLine()
			imgui.BeginDisabled(.MultiInstance not_in at.flags && .NoInitialInstance not_in at.flags)
			if imgui.Button("Remove extra instances") {
				if .NoInitialInstance in at.flags {
					remove_window_instance(at, 0)
				}

				for i in 1..<len(at.instances) {
					remove_window_instance(at, i)
				}
			}
			imgui.EndDisabled()

			imgui.BeginTable("##instances", 3, imgui.TableFlags_BordersInnerV) or_continue
			defer imgui.EndTable()

			for instance, i in at.instances {
				if instance == nil {continue}
				imgui.TableNextRow()
				imgui.PushIDInt(auto_cast i)
				defer imgui.PopID()

				if imgui.TableSetColumnIndex(0) {
					imgui.Text("%d", i32(i))
				}

				if imgui.TableSetColumnIndex(1) {
					if (.MultiInstance in at.flags && i > 0) || .NoInitialInstance in at.flags {
						if imgui.Selectable("Remove") {
							want_remove_instance = i
						}
					}
				}

				if imgui.TableSetColumnIndex(2) {
					if imgui.Selectable("Bring forward") {
						instance.want_bring_to_front = true
					}
				}
			}

			if want_remove_instance != -1 {remove_window_instance(at, want_remove_instance)}
		}
	}
}