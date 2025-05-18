package server

Sort_Order :: enum {
	Ascending,
	Descending,
}

Error :: enum {
	None,
	NameExists,
	FileError,
}

Path :: [512]u8
