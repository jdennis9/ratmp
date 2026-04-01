#ifdef __linux__
#include <gtk/gtk.h>
#include <libappindicator/app-indicator.h>
#include <stdio.h>

#include "../common.h"

enum {
	MESSAGE_TYPE_INFO,
	MESSAGE_TYPE_YES_NO,
	MESSAGE_TYPE_OK_CANCEL,
	MESSAGE_TYPE_YES_NO_CANCEL,
};

enum {
	URGENCY_INFO,
	URGENCY_QUESTION,
	URGENCY_WARNING,
	URGENCY_ERROR,
};

extern "C" void linux_misc_init() {
	gtk_init(NULL, NULL);
}

extern "C" int linux_misc_message_box(
	const char *message,
	int type, int urgency
) {
	GtkMessageType message_type;
	GtkButtonsType buttons;

	switch (type) {
	case MESSAGE_TYPE_INFO:
		buttons = GTK_BUTTONS_OK;
		break;
	case MESSAGE_TYPE_YES_NO:
		buttons = GTK_BUTTONS_YES_NO;
		break;
	case MESSAGE_TYPE_OK_CANCEL:
		buttons = GTK_BUTTONS_OK_CANCEL;
		break;
	default: return false;
	}

	switch (urgency) {
	case URGENCY_INFO:
		message_type = GTK_MESSAGE_INFO;
		break;
	case URGENCY_QUESTION:
		message_type = GTK_MESSAGE_QUESTION;
		break;
	case URGENCY_WARNING:
		message_type = GTK_MESSAGE_WARNING;
		break;
	case URGENCY_ERROR:
		message_type = GTK_MESSAGE_ERROR;
		break;
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

static AppIndicator *global_app_indicator;
static GtkMenuShell *global_tray_menu;
static void (*systray_event_handler)(int event);

struct Tray_Button {
	const char *name;
	int event;
};

#define MAX_TRAY_BUTTONS 32
static Tray_Button global_tray_buttons[MAX_TRAY_BUTTONS];
static int global_tray_button_count;

static void tray_menu_callback(GtkMenuItem *item, gpointer data) {
	const char *label = gtk_menu_item_get_label(item);

	if (!systray_event_handler) return;

	for (int i = 0; i < global_tray_button_count; ++i) {
		Tray_Button butt = global_tray_buttons[i];
		if (!strcmp(label, butt.name)) {
			systray_event_handler(butt.event);
		}
	}
}

extern "C" void linux_misc_systray_init(
	void (*event_handler)(int event),
	Tray_Button *buttons,
	int button_count
) {
	GtkWidget *item;
	const char *icon = "ratmp";

	systray_event_handler = event_handler;

	global_app_indicator = app_indicator_new("ratmp", icon, APP_INDICATOR_CATEGORY_APPLICATION_STATUS);

	global_tray_menu = GTK_MENU_SHELL(gtk_menu_new());
	
	global_tray_button_count = button_count;
	
	for (int i = 0; i < button_count; ++i) {
		Tray_Button butt = buttons[i];
		global_tray_buttons[i] = butt;
		item = gtk_menu_item_new_with_label(butt.name);
		gtk_widget_show(item);
		gtk_menu_shell_append(global_tray_menu, item);
		g_signal_connect(item, "activate", G_CALLBACK(tray_menu_callback), NULL);
	}
	
	app_indicator_set_status(global_app_indicator, APP_INDICATOR_STATUS_ACTIVE);
	app_indicator_set_icon(global_app_indicator, icon);
	app_indicator_set_menu(global_app_indicator, GTK_MENU(global_tray_menu));
}

extern "C" void linux_misc_gtk_main_iteration(bool blocking) {
	gtk_main_iteration_do(blocking);
}

#endif
