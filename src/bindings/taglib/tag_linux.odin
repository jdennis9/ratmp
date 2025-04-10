package taglib;

wrapped_open :: proc(path: cstring) -> File {
	return file_new(path);
}
