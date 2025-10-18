package dbus

import "core:c"

foreign import lib "system:dbus"

Connection :: struct {}

BusType :: enum c.int {
	SESSION,
	SYSTEM,
	STARTER,
}

Error :: struct {
	name: cstring,
	message: cstring,
	dummy: [5]c.uint,
	padding1: rawptr,
}

Message :: struct {}

bool_t :: b32

@(link_prefix="dbus_")
foreign lib {
	bus_get :: proc(type: BusType, error: ^Error) -> ^Connection ---
	bus_register :: proc(connection: ^Connection, error: ^Error) -> bool_t ---
	bus_set_unique_name :: proc(connection: ^Connection, name: cstring) -> bool_t ---
	bus_get_unique_name :: proc(connection: ^Connection) -> cstring ---

	message_new :: proc(message_type: c.int) -> ^Message ---
	message_method_call :: proc(
		dest: cstring, path: cstring,
		iface: cstring, method: cstring
	) -> ^Message ---
}
