package util;

import "core:c";
import "core:sys/posix";
import "core:strings";

message_box :: proc(title: string, type: Message_Box_Type, message: string) -> bool {
	dialog_type: cstring;

	message_cstring := strings.clone_to_cstring(message);
	defer delete(message_cstring); 

	switch type {
		case .Message:
			dialog_type = "--info";
		case .OkCancel:
			dialog_type = "--question";
		case .YesNo:
			dialog_type = "--question";
	};

	cmd := []cstring {
		dialog_type,
		message_cstring,
	};

	status: c.int;
	if posix.fork() != 0 {
		posix.wait(&status);
	}
	else {
		posix.execv("/usr/bin/zenity", &cmd[0]);
	}

	return status == 0;
}
