#ifdef __linux__
#include <gtk/gtk.h>
#include <stdio.h>

enum {
	MESSAGE_TYPE_INFO,
	MESSAGE_TYPE_WARNING,
	MESSAGE_TYPE_YES_NO,
	MESSAGE_TYPE_OK_CANCEL,
};

extern "C" void linux_misc_init() {
	gtk_init(NULL, NULL);
}

extern "C" bool linux_misc_message_box(
	const char *message,
	int type
) {
	GtkMessageType message_type;
	GtkButtonsType buttons;

	switch (type) {
		case MESSAGE_TYPE_INFO:
			message_type = GTK_MESSAGE_INFO;
			buttons = GTK_BUTTONS_NONE;
			break;
		case MESSAGE_TYPE_WARNING:
			message_type = GTK_MESSAGE_WARNING;
			buttons = GTK_BUTTONS_NONE;
			break;
		case MESSAGE_TYPE_YES_NO:
			message_type = GTK_MESSAGE_QUESTION;
			buttons = GTK_BUTTONS_YES_NO;
			break;
		case MESSAGE_TYPE_OK_CANCEL:
			message_type = GTK_MESSAGE_QUESTION;
			buttons = GTK_BUTTONS_OK_CANCEL;
			break;
		default: return false;
	}

	GtkWidget *dialog = gtk_message_dialog_new(
		NULL,
		(GtkDialogFlags)0,
		message_type,
		buttons,
		message
	);

	gint response = gtk_dialog_run(GTK_DIALOG(dialog));
	gtk_widget_destroy(GTK_WIDGET(dialog));

	switch (response) {
		case GTK_RESPONSE_DELETE_EVENT:
		case GTK_RESPONSE_NO:
		return false;
		case GTK_RESPONSE_YES:
		return true;
	}

	return true;
}
#endif
