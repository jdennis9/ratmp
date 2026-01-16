#include "../media_controls.h"
#include "introspection.h"
#include <glib.h>
#include <gio/gio.h>
#include <pthread.h>

#define ARRAY_LENGTH(arr) (sizeof(arr) / sizeof((arr)[0]))

#define SERVER_INTERFACE_NAME "org.mpris.MediaPlayer2.ratmp"
#define INTERFACE_MPRIS_MEDIAPLAYER2 "org.mpris.MediaPlayer2"
#define INTERFACE_MPRIS_MEDIAPLAYER2_PLAYER "org.mpris.MediaPlayer2.Player"

static const char *SUPPORTED_URI_SCHEMES[] = {
	"file",
};

static const char *SUPPORTED_MIME_TYPES[] = {
	"audio/mp3",
};

static GDBusInterfaceVTable server_vtable;

template<typename T>
struct Array_Property {
	T const *values;
	int length;
};

static struct {
	pthread_t thread;
	GDBusNodeInfo *introspection_info;
	GDBusConnection *conn;
	GDBusProxy *proxy;
	Handler *handler;
	void *handler_data;
	bool enabled;
} mc;

static struct {
	gboolean can_quit;
	gboolean fullscreen;
	gboolean can_set_fullscreen;
	gboolean can_raise;
	gboolean has_track_list;
	const char *identity;
	const char *desktop_entry;
	Array_Property<const char *> supported_uri_schemes;
	Array_Property<const char *> supported_mime_types;
} server_props;

static struct {
	const char *playback_status;
	const char *loop_status;
	double rate;
	gboolean shuffle;
	Track_Info metadata;
	double volume;
	int64_t position;
	double minimum_rate;
	double maximum_rate;
	gboolean can_go_next;
	gboolean can_go_previous;
	gboolean can_play;
	gboolean can_pause;
	gboolean can_seek;
	gboolean can_control;
} player_props;

enum {
	PROPERTY_TYPE_STRING,
	PROPERTY_TYPE_STRING_ARRAY,
	PROPERTY_TYPE_BOOL,
	PROPERTY_TYPE_DOUBLE,
	PROPERTY_TYPE_INT64,
	PROPERTY_TYPE_TRACK_INFO,
};

struct Mapped_Property {
	const char *name;
	void *value;
	int type;
};

static Mapped_Property server_props_map[] = {
	{"CanQuit", &server_props.can_quit, PROPERTY_TYPE_BOOL},
	{"Fullscreen", &server_props.can_quit, PROPERTY_TYPE_BOOL},
	{"CanSetFullscreen", &server_props.can_set_fullscreen, PROPERTY_TYPE_BOOL},
	{"CanRaise", &server_props.can_raise, PROPERTY_TYPE_BOOL},
	{"HasTrackList", &server_props.has_track_list, PROPERTY_TYPE_BOOL},
	{"DesktopEntry", &server_props.desktop_entry, PROPERTY_TYPE_STRING},
	{"Identity", &server_props.identity, PROPERTY_TYPE_STRING},
	{"SupportedUriSchemes", &server_props.supported_uri_schemes, PROPERTY_TYPE_STRING_ARRAY},
	{"SupportedMimeTypes", &server_props.supported_mime_types, PROPERTY_TYPE_STRING_ARRAY},
};

static Mapped_Property player_props_map[] = {
	{"PlaybackStatus", &player_props.playback_status, PROPERTY_TYPE_STRING},
	{"LoopStatus", &player_props.loop_status, PROPERTY_TYPE_STRING},
	{"Rate", &player_props.rate, PROPERTY_TYPE_DOUBLE},
	{"Shuffle", &player_props.shuffle, PROPERTY_TYPE_BOOL},
	{"Volume", &player_props.volume, PROPERTY_TYPE_DOUBLE},
	{"Position", &player_props.position, PROPERTY_TYPE_INT64},
	{"MinimumRate", &player_props.minimum_rate, PROPERTY_TYPE_DOUBLE},
	{"MaximumRate", &player_props.maximum_rate, PROPERTY_TYPE_DOUBLE},
	{"CanGoNext", &player_props.can_go_next, PROPERTY_TYPE_BOOL},
	{"CanGoPrevious", &player_props.can_go_previous, PROPERTY_TYPE_BOOL},
	{"CanPlay", &player_props.can_play, PROPERTY_TYPE_BOOL},
	{"CanPause", &player_props.can_pause, PROPERTY_TYPE_BOOL},
	{"CanSeek", &player_props.can_seek, PROPERTY_TYPE_BOOL},
	{"CanControl", &player_props.can_control, PROPERTY_TYPE_BOOL},
	{"Metadata", &player_props.metadata, PROPERTY_TYPE_TRACK_INFO},
};

static GVariant *mapped_property_to_variant(const Mapped_Property& p) {
	switch (p.type) {
		case PROPERTY_TYPE_STRING: {
			const char *value = *(const char**)p.value;
			return g_variant_new_string(value);
		}
		case PROPERTY_TYPE_BOOL: {
			bool value = *(bool*)p.value;
			return g_variant_new_boolean(value);
		}
		case PROPERTY_TYPE_DOUBLE: {
			double value = *(double*)p.value;
			return g_variant_new_double(value);
		}
		case PROPERTY_TYPE_INT64: {
			int64_t value = *(int64_t*)p.value;
			return g_variant_new_int64(value);
		}
		case PROPERTY_TYPE_STRING_ARRAY: {
			Array_Property<const char *> value = *(Array_Property<const char *>*)p.value;
			GVariant **children = new GVariant*[value.length];
			for (int i = 0; i < value.length; ++i) {
				children[i] = g_variant_new_string(value.values[i]);
			}

			GVariant *array = g_variant_new_array(G_VARIANT_TYPE_STRING, children, value.length);

			delete children;
			return array;
		}
		case PROPERTY_TYPE_TRACK_INFO: {
			GVariant *result = NULL;
			Track_Info *info = (Track_Info*)p.value;
			GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);

			if (info->artist)
				g_variant_builder_add(builder, "{sv}", "xesam:artist", g_variant_new_string(info->artist));
			if (info->album)
				g_variant_builder_add(builder, "{sv}", "xesam:album", g_variant_new_string(info->album));
			if (info->genre)
				g_variant_builder_add(builder, "{sv}", "xesam:genre", g_variant_new_string(info->genre));
			if (info->title)
				g_variant_builder_add(builder, "{sv}", "xesam:title", g_variant_new_string(info->title));
			if (info->path)
				g_variant_builder_add(builder, "{sv}", "mpris:track_id", g_variant_new_string(info->path));
			else
				g_variant_builder_add(builder, "{sv}", "mpris:track_id", g_variant_new_string("/"));

			result = g_variant_new("a{sv}", builder);
			return result;
		}
	}

	g_assert(false);
	return NULL;
}

static GVariant *lookup_property(const char *name, const Mapped_Property *props, int count) {
	for (int i = 0; i < count; ++i) {
		const Mapped_Property &p = props[i];

		if (!strcmp(name, p.name)) {
			return mapped_property_to_variant(p);
		}
	}

	return NULL;
}

static GVariant *get_server_property(const char *name) {
	return lookup_property(name, server_props_map, ARRAY_LENGTH(server_props_map));
}

static GVariant *get_player_property(const char *name) {
	return lookup_property(name, player_props_map, ARRAY_LENGTH(player_props_map));
}

static void call_server_method(const char *name, GVariant *parameters, GDBusMethodInvocation *invocation) {
}

static void call_player_method(const char *name, GVariant *parameters, GDBusMethodInvocation *invocation) {
	if (!strcmp(name, "Play")) {
		mc.handler(mc.handler_data, SIGNAL_PLAY);
	}
	else if (!strcmp(name, "Pause")) {
		mc.handler(mc.handler_data, SIGNAL_PAUSE);
	}
	else if (!strcmp(name, "Next")) {
		mc.handler(mc.handler_data, SIGNAL_NEXT);
	}
	else if (!strcmp(name, "Previous")) {
		mc.handler(mc.handler_data, SIGNAL_PREV);
	}
	else if (!strcmp(name, "Stop")) {
		mc.handler(mc.handler_data, SIGNAL_STOP);
	}

	g_dbus_method_invocation_return_value(invocation, NULL);
}

static void handle_method_call(
	GDBusConnection *connection,
	const char *sender,
	const char *object_path,
	const char *interface,
	const char *method,
	GVariant *parameters,
	GDBusMethodInvocation *invocation,
	void *user_data
) {
	if (!strcmp(interface, INTERFACE_MPRIS_MEDIAPLAYER2)) {
		call_server_method(method, parameters, invocation);
	}
	else if (!strcmp(interface, INTERFACE_MPRIS_MEDIAPLAYER2_PLAYER)) {
		call_player_method(method, parameters, invocation);
	}
}

static GVariant *handle_get_property(
	GDBusConnection *conn,
	const char *sender,
	const char *object_path,
	const char *interface,
	const char *property,
	GError **error,
	void *user_data
) {
	GVariant *reply = NULL;

	if (!strcmp(interface, INTERFACE_MPRIS_MEDIAPLAYER2)) {
		reply = get_server_property(property);
	}
	else if (!strcmp(interface, INTERFACE_MPRIS_MEDIAPLAYER2_PLAYER)) {
		reply = get_player_property(property);
	}

	return reply;
}

static gboolean handle_set_property(
	GDBusConnection *conn,
	const char *sender,
	const char *object_path,
	const char *interface,
	const char *property,
	GVariant *value,
	GError **error,
	void *userdata
) {

	return true;
}

static bool check(GError **error, const char *message = NULL) {
	if (*error != NULL) {
		if (message) {
			g_printerr("%s: %s\n", message, (*error)->message);
		}
		else {
			g_printerr("%s\n", (*error)->message);
		}
		g_clear_error(error);
		return false;
	}

	return true;
}

static void signal_player_property_change(const char **names, int count) {
	GError *error = NULL;
	GVariantBuilder *builder;
	builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);

	for (int iname = 0; iname < count; ++iname) {
		const char *name = names[iname];

		for (int iprop = 0; iprop < ARRAY_LENGTH(player_props_map); ++iprop) {
			const Mapped_Property& prop = player_props_map[iprop];

			if (!strcmp(prop.name, name)) {
				GVariant *value = mapped_property_to_variant(prop);
				g_variant_builder_add(builder, "{sv}", name, value);
			}
		}
	}

	g_dbus_connection_emit_signal(mc.conn, NULL,
		"/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged",
		g_variant_new(
			"(sa{sv}as)",
			INTERFACE_MPRIS_MEDIAPLAYER2_PLAYER,
			builder,
			NULL
		),
		&error
	);

	check(&error);
}

static void on_bus_acquired(GDBusConnection *conn, const char *name, void *userdata) {
	guint id;
	GError *error;

	id = g_dbus_connection_register_object(
		conn,
		"/org/mpris/MediaPlayer2",
		mc.introspection_info->interfaces[2],
		&server_vtable,
		NULL, NULL, NULL
	);

	g_assert(id > 0);

	id = g_dbus_connection_register_object(
		conn,
		"/org/mpris/MediaPlayer2",
		mc.introspection_info->interfaces[3],
		&server_vtable,
		NULL, NULL, NULL
	);

	g_assert(id > 0);

	mc.proxy = g_dbus_proxy_new_for_bus_sync(
		G_BUS_TYPE_SESSION,
		G_DBUS_PROXY_FLAGS_NONE,
		NULL,
		"org.freedesktop.DBus.Properties",
		"/org/freedesktop/DBus/Properties",
		SERVER_INTERFACE_NAME,
		NULL,
		&error
	);

	mc.conn = conn;

	const char *player_prop_names[ARRAY_LENGTH(player_props_map)];

	for (int i = 0; i < ARRAY_LENGTH(player_props_map); ++i) {
		player_prop_names[i] = player_props_map[i].name;
	}

	signal_player_property_change(player_prop_names, ARRAY_LENGTH(player_prop_names));
}

static void on_name_acquired(GDBusConnection *conn, const char *name, void *userdata) {
	g_print("Acquired bus name: %s", name);
}

static void on_name_lost(GDBusConnection *conn, const char *name, void *userdata) {
}

static void *run_dbus_session(void *dont_care) {
	GMainLoop *loop;
	GError *error = NULL;
	guint owner_id;

	mc.introspection_info = g_dbus_node_info_new_for_xml(
		server_introspection_xml, &error
	);

	g_assert(mc.introspection_info != NULL);

	owner_id = g_bus_own_name(
		G_BUS_TYPE_SESSION,
		SERVER_INTERFACE_NAME,
		G_BUS_NAME_OWNER_FLAGS_NONE,
		on_bus_acquired,
		on_name_acquired,
		on_name_lost,
		NULL, NULL
	);

	GMainContext *ctx = g_main_context_new();
	loop = g_main_loop_new(ctx, false);
	g_main_loop_run(loop);
	g_bus_unown_name(owner_id);
	g_dbus_node_info_unref(mc.introspection_info);

	return NULL;
}

void enable(Handler *handler, void *data) {
	mc.handler = handler;
	mc.handler_data = data;
	
	server_vtable.method_call = handle_method_call;
	server_vtable.get_property = handle_get_property;
	server_vtable.set_property = handle_set_property;
	
	server_props.identity = "RAT MP";
	server_props.desktop_entry = "ratmp";
	server_props.supported_mime_types.values = SUPPORTED_MIME_TYPES;
	server_props.supported_mime_types.length = ARRAY_LENGTH(SUPPORTED_MIME_TYPES);
	server_props.supported_uri_schemes.values = SUPPORTED_URI_SCHEMES;
	server_props.supported_uri_schemes.length = ARRAY_LENGTH(SUPPORTED_URI_SCHEMES);
	
	player_props.can_go_next = true;
	player_props.can_go_previous = true;
	player_props.can_play = true;
	player_props.can_pause = true;
	//player_props.can_seek = true;
	player_props.can_control = true;
	player_props.loop_status = "Repeat Playlist";
	player_props.playback_status = "Stopped";
	player_props.rate = 1;
	player_props.maximum_rate = 1;
	player_props.minimum_rate = 1;
	
	mc.enabled = true;
	pthread_create(&mc.thread, NULL, run_dbus_session, NULL);
}

void disable() {
}

void set_state(int32_t state) {
	const char *value;
	if (!mc.enabled) return;

	switch (state) {
		case STATE_PLAYING: value = "Playing"; break;
		case STATE_PAUSED: value = "Paused"; break;
		case STATE_STOPPED: value = "Stopped"; break;
	}

	const char *prop_names[] = {
		"PlaybackStatus",
	};

	player_props.playback_status = value;

	signal_player_property_change(prop_names, ARRAY_LENGTH(prop_names));
}

void set_track_info(const Track_Info *info) {
	Track_Info *out = &player_props.metadata;
	if (!mc.enabled) return;

	if (out->album) free((void*)out->album);
	if (out->artist) free((void*)out->artist);
	if (out->genre) free((void*)out->genre);
	if (out->title) free((void*)out->title);
	if (out->path) free((void*)out->path);

	const char *prop_names[] = {
		"Metadata",
	};

	player_props.metadata.album = strdup(info->album);
	player_props.metadata.artist = strdup(info->artist);
	player_props.metadata.genre = strdup(info->genre);
	player_props.metadata.title = strdup(info->title);
	player_props.metadata.path = strdup(info->path);

	signal_player_property_change(prop_names, ARRAY_LENGTH(prop_names));
}
