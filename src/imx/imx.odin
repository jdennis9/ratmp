package imx

import "core:log"
import "core:mem"
import "base:runtime"
import "core:slice"
import "core:fmt"
import "core:reflect"
import imgui "src:thirdparty/odin-imgui"

text_unformatted :: proc(str: string) {
	base := raw_data(transmute([]u8) str)
	imgui.TextUnformatted(cstring(base), cstring(&base[len(str)]))
}

text :: proc($BUF_SIZE: uint, args: ..any) {
	buf: [BUF_SIZE]u8
	text_unformatted(fmt.bprint(buf[:], ..args))
}

textf :: proc($BUF_SIZE: uint, format: string, args: ..any) {
	buf: [BUF_SIZE]u8
	text_unformatted(fmt.bprintf(buf[:], format, ..args))
}


typeid_to_data_type :: proc(t: typeid) -> (s: imgui.DataType, ok: bool) {
	ok = true
	switch t {
		case f32: s = .Float
		case f64: s = .Double
		case i8: s = .S8
		case i16: s = .S16
		case i32: s = .S32
		case int, i64: s = .S64
		case u8: s = .U8
		case u16: s = .U16
		case u32: s = .U32
		case uint, u64: s = .U64
		case: ok = false
	}
	return
}

Type_Edit_Callback :: #type proc(label: cstring, ptr: rawptr, T: typeid, callbacks: map[typeid]Type_Edit_Callback = nil, callback_data: rawptr = nil) -> bool

edit_any :: proc(label: cstring, ptr: rawptr, T: typeid, callbacks: map[typeid]Type_Edit_Callback = nil, callback_data: rawptr = nil) -> bool {
	type := type_info_of(T)
	type = reflect.type_info_base(type)

	if cb, have_cb := callbacks[T]; have_cb {
		return cb(label, ptr, T, callbacks, callback_data)
	}

	#partial switch variant in type.variant {
	case runtime.Type_Info_Struct:
		imgui.TreeNodeEx(label, {.DefaultOpen}) or_return
		for fi in 0..<variant.field_count {
			name_buf: [128]u8
			name := cstring(&name_buf[0])
			field := reflect.struct_field_at(type.id, auto_cast fi)
			field_type := reflect.type_info_base(field.type)
			field_ptr := raw_data((cast([^]byte) ptr)[field.offset:][:field.type.size])
			copy(name_buf[:len(name_buf)-1], field.name)
			edit_any(name, field_ptr, field.type.id, callbacks, callback_data)
		}
		imgui.TreePop()

	case runtime.Type_Info_Array:
		elem := reflect.type_info_base(variant.elem)
		if variant.count <= 4 {
			dt := typeid_to_data_type(variant.elem.id) or_break
			imgui.InputScalarN(label, dt, ptr, auto_cast variant.count)
		}
		else {
			imgui.TreeNodeEx(label, {.DefaultOpen}) or_return
			for i in 0..<variant.count {
				elem_name_buf: [32]u8
				elem_name := cstring(&elem_name_buf[0])
				elem_ptr := mem.ptr_offset(cast(^byte) ptr, elem.size * i)
				fmt.bprint(elem_name_buf[:31], "[", i, "]", sep="")
				edit_any(elem_name, elem_ptr, elem.id, callbacks, callback_data)
			}
			imgui.TreePop()
		}

	case runtime.Type_Info_Integer, runtime.Type_Info_Float:
		dt := typeid_to_data_type(type.id) or_return
		return imgui.InputScalar(label, dt, ptr)

	case runtime.Type_Info_Boolean:
		value: bool
		data := any{ptr, T}
		switch v in data {
			case bool: value = v
			case b16: value = bool(v)
			case b32: value = bool(v)
			case b64: value = bool(v)
		}
		if imgui.Checkbox(label, &value) {
			switch &v in data {
				case bool: v = value
				case b16: v = b16(value)
				case b32: v = b32(value)
				case b64: v = b64(value)
			}
			return true
		}

		return false
	}

	return false
}

begin_combo :: proc($BUF_SIZE: uint, label: cstring, preview: string) -> bool {
	buf: [BUF_SIZE]u8
	copy(buf[:BUF_SIZE-1], preview)
	return imgui.BeginCombo(label, cstring(&buf[0]))
}

menu_item :: proc($BUF_SIZE: uint, label: string) -> bool {
	buf: [BUF_SIZE]u8
	copy(buf[:BUF_SIZE-1], label)
	return imgui.MenuItem(cstring(&buf[0]))
}
