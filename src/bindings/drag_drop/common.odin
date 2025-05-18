package drag_drop

Interface :: struct {
	add_file: proc "c" (path: cstring),
	begin: proc "c" (),
	mouse_over: proc "c" (x: f32, y: f32),
	cancel: proc "c" (),
	drop: proc "c" (),
}