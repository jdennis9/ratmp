/*
   Copyright 2024 Jamie Dennis

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
#include "ui.h"
#include "tracklist.h"
#include "metadata.h"
#include "widgets.h"
#include "stream.h"
#include "files.h"
#include "theme.h"
#include "main.h"
#include "stats.h"
#include "util/auto_array_impl.h"
#include <math.h>
#include <imgui.h>
#include <ini.h>
#include <mutex>
#include <ctype.h>
extern "C" {
#include <libavcodec/avcodec.h>
}

static const char DEFAULT_LAYOUT_INI[] =
"[Window][Main Window]\n"
"Collapsed=0\n"
"\n"
"[Window][Debug##Default]\n"
"Collapsed=0\n"
"\n"
"[Window][Navigation]\n"
"Collapsed=0\n"
"DockId=0x00000001,0\n"
"\n"
"[Window][Control Panel]\n"
"Collapsed=0\n"
"DockId=0x00000004,0\n"
"\n"
"[Window][Track View]\n"
"Collapsed=0\n"
"DockId=0x00000002,0\n"
"\n"
"[Docking][Data]\n"
"DockSpace     ID=0xF97EAFDC Window=0x8FE86BE8 Pos=0,20 Size=1858,1000 Split=Y\n"
"  DockNode    ID=0x00000003 Parent=0xF97EAFDC SizeRef=1858,917 Split=X\n"
"    DockNode  ID=0x00000001 Parent=0x00000003 SizeRef=294,1000 CentralNode=1 Selected=0x5127E491\n"
"    DockNode  ID=0x00000002 Parent=0x00000003 SizeRef=1562,1000 Selected=0xD2ADD0F1\n"
"  DockNode    ID=0x00000004 Parent=0xF97EAFDC SizeRef=1858,81 HiddenTabBar=1 Selected=0xA008732B\n"
;

enum Main_View {
	MAIN_VIEW_TRACKS,
	MAIN_VIEW_ALBUMS,
};

enum {
	PLAYLIST_LIBRARY,
	PLAYLIST_QUEUE,
	PLAYLIST_USER,
};

struct Layout {
	char name[64];
};

struct Optional_Window {
	bool show;
	bool bring_to_front;
};

static struct {
	Optional_Window windows[UI_WINDOW__COUNT];
	Tracklist search_results;
	Stream_State state;
	int32 queue_position;
	Auto_Array<Tracklist> playlists;
	Auto_Array<uint32> playlist_order; // Order of user playlists
	int32 renaming_playlist;
	int32 selected_playlist;
	int32 queued_playlist;
	Main_View main_view;
	ImTextureID thumbnail;
	ImTextureID waveform_image;
	Tracklist drag_drop_payload;
	Track playing_track;
	bool shuffle_enabled;
	bool dirty_theme;
	Auto_Array<Layout> layouts;
} G;

const char *ui_get_window_name(UI_Window window) {
	switch (window) {
		case UI_WINDOW_MISSING_TRACKS: return "Missing Tracks";
		case UI_WINDOW_PREFERENCES: return "Preferences";
		case UI_WINDOW_THEME_EDITOR: return "Theme";
		case UI_WINDOW_PLAYBACK_STATS: return "Playback Statistics";
		case UI_WINDOW_SEARCH_RESULTS: return "Search Results";
		case UI_WINDOW_ALBUM_LIST: return "Album List";
		case UI_WINDOW__COUNT: return "<unknown>";
	}
	
	return "<unknown>";
}

UI_Window ui_get_window_from_name(const char *name) {
	for (uint32 i = 0; i < UI_WINDOW__COUNT; ++i) {
		if (!strcmp(ui_get_window_name((UI_Window)i), name)) {
			return (UI_Window)i;
		}
	}
	
	return UI_WINDOW__COUNT;
}

void ui_show_window(UI_Window window) {
	if (window < 0 || window > UI_WINDOW__COUNT) return;
	G.windows[window].show = true;
}

void ui_bring_window_to_front(UI_Window window) {
	if (window < 0 || window > UI_WINDOW__COUNT) return;
	G.windows[window].show = true;
	G.windows[window].bring_to_front = true;
}

bool ui_is_window_open(UI_Window window) {
	if (window < 0 || window > UI_WINDOW__COUNT) return false;
	return G.windows[window].show;
}

static void show_config_editor_gui();
static void show_hotkey_gui();
static void show_about_gui();
static void queue_tracklist(const Tracklist &tracklist);
static void refresh_layouts();

static bool is_track_playing(const Track &track) {
	if (G.state == STREAM_STATE_STOPPED) return false;
	return G.playing_track.metadata == track.metadata;
}

static bool play_track_at(uint32 iplaylist, int32 position, bool translate_index = false) {
	char path[512];
	Tracklist &tracklist = G.playlists[PLAYLIST_QUEUE];
	bool ok;
	
	if (!G.playlists[iplaylist].length()) return true;
	
	if (iplaylist == PLAYLIST_QUEUE) {
		position = tracklist.repeat(position);
		const Track &track = tracklist[position];
		retrieve_file_path(track.path, path, sizeof(path));
		ok = stream_load(path);
		if (ok) {
			increment_track_play_count(track);
			save_stats();
		}
		G.queue_position = position;
		G.queued_playlist = PLAYLIST_QUEUE;
		G.playing_track = track;
		return ok;
	}
	
	if (iplaylist != G.queued_playlist) {
		G.queued_playlist = iplaylist;
		tracklist.clear();
		G.playlists[iplaylist].copy(&tracklist);
		if (G.shuffle_enabled) tracklist.shuffle();
	}

	if (tracklist.length() == 0) return true;

	// If this track was selected manually from the track list
	// we need to translate the index to match for that track in the queue
	if (translate_index && G.shuffle_enabled) {
		position = tracklist.index_of_track(G.playlists[iplaylist][position]);
		if (position < 0) return false;
	}

	position = tracklist.repeat(position);
	G.queue_position =  position;

	const Track &current = tracklist[position];
	retrieve_file_path(current.path, path, sizeof(path));
	ok = stream_load(path);
	if (ok) {
		increment_track_play_count(current);
		save_stats();
	}
	G.playing_track = current;
	return ok;
}

static void goto_next_track() {
	if (G.queued_playlist < 0) return;
	for (uint32 i = 1; i <= G.playlists[G.queued_playlist].length(); ++i) {
		if (play_track_at(G.queued_playlist, G.queue_position + 1)) break;
	}
}

static void goto_previous_track() {
	if (G.queued_playlist < 0) return;
	for (uint32 i = 1; i <= G.playlists[G.queued_playlist].length(); ++i) {
		if (play_track_at(G.queued_playlist, G.queue_position - 1)) break;
	}
}

void ui_next_track() {
	goto_next_track();
}

static void quick_sort_playlists(Auto_Array<uint32>& order, int low, int high) {
	int pivot;
	if (low < high) {
		pivot = high;
		{
			int i = low-1;
			for (int j = low; j <= high-1; ++j) {
				bool j_before_pivot = compare_strings_case_insensitive(G.playlists[order[j]].name,
																	   G.playlists[order[pivot]].name) == -1;
				if (j_before_pivot) {
					i++;
					SWAP(G.playlists[order[i]], G.playlists[order[j]]);
				}
			}
			SWAP(G.playlists[order[i+1]], G.playlists[order[high]]);
			pivot = i + 1;
		}
		
		quick_sort_playlists(order, low, pivot-1);
		quick_sort_playlists(order, pivot+1, high);
	}
}

static void sort_playlists() {
	uint32 count = G.playlists.m_count;
	G.playlist_order.reset();
	for (uint32 i = PLAYLIST_USER; i < G.playlists.m_count; ++i) 
		G.playlist_order.append(i);
	quick_sort_playlists(G.playlist_order, 0, G.playlist_order.m_count-1);
}

static int32 show_playlist_dropdown_selector() {
	uint32 playlist_count = G.playlists.length();
	char name_id[128];

	for (uint32 i = PLAYLIST_USER; i < playlist_count; ++i) {
		snprintf(name_id, 128, "%s##%s", G.playlists[i].name, G.playlists[i].get_filename());
		if (ImGui::Selectable(name_id)) {
			return i;
		}
	}

	return -1;
}

static void show_track_list_missing_tracks_ui(Tracklist& tracklist) {
	Auto_Array<Path_Ref>& tracks = tracklist.m_missing_tracks;
	ImGuiID rename_popup_id = ImGui::GetID("Rename");
	static uint32 renaming_file = 0;
	static char old_path[512];
	static char new_path[512];
	const ImGuiStyle& style = ImGui::GetStyle();
	
#ifndef NDEBUG
	if (ImGui::Button("Add test file")) {
		Path_Ref test_path = store_file_path("test_missing_file.mp3");
		tracks.append(test_path);
	}
#endif
	
	ImGui::Text("Edit missing tracks for playlist: %s", tracklist.name);
	ImGui::Separator();
	
	if (ImGui::Button("Remove all")) {
		const char *message = 
			"Are you sure to want to remove all missing tracks from this playlist?"
			" This cannot be undone.";
		bool remove_all = show_confirmation_dialog("Remove All Missing Tracks", message);
		if (remove_all) {
			tracklist.remove_missing_tracks();
			tracklist.save_to_file();
			return;
		}
	}
	
	if (ImGui::BeginTable("##missing_tracks_table", 2, ImGuiTableFlags_RowBg|ImGuiTableFlags_BordersInner)) {
		for (uint32 i = 0; i < tracks.m_count; ++i) {
			char path[512];
			retrieve_file_path(tracks[i], path, sizeof(path));
			
			ImGui::TableNextRow();
			ImGui::TableSetColumnIndex(0);
			ImGui::TextUnformatted(path);
			ImGui::TableSetColumnIndex(1);
			if (ImGui::Selectable(lazy_format("Change##%u", i))) {
				renaming_file = i;
				strncpy_s(old_path, path, sizeof(old_path)-1);
				strncpy_s(new_path, path, sizeof(new_path)-1);
				ImGui::OpenPopup(rename_popup_id);
			}
		}
		ImGui::EndTable();
	}
	
	if (renaming_file < tracks.m_count && ImGui::BeginPopup("Rename")) {
		bool commit = false;
		ImGui::Text("Rename file \"%s\" to:", old_path);
		commit |= ImGui::InputText("##new_path", new_path, sizeof(new_path),
								   ImGuiInputTextFlags_EnterReturnsTrue);
		if (ImGui::Button("Browse")) {
			select_file_dialog(new_path, sizeof(new_path));
		}
		ImGui::SameLine();
		commit |= ImGui::Button("OK");
		
		ImGui::SameLine();
		if (ImGui::Button("Cancel")) ImGui::CloseCurrentPopup();
		
		if (commit) {
			if (tracklist.add(new_path)) {
				tracks.remove(renaming_file);
				tracklist.save_to_file();
			}
			else {
				show_message_box(MESSAGE_BOX_WARNING, "Not a playable file");
			}
			ImGui::CloseCurrentPopup();
		}
		
		ImGui::EndPopup();
	}
}

static int32 show_track_list_range(Tracklist& tracklist, int32 playlist_id, uint32 start, uint32 end, const Track_Filter *filter, bool jump_to_playing) {
	bool editable = (playlist_id != PLAYLIST_LIBRARY) && (playlist_id >= 0);
	bool queueable = playlist_id != PLAYLIST_QUEUE;
	bool filter_enabled = filter && filter->enabled && filter->filter[0];
	ImGuiIO &io = ImGui::GetIO();
	int32 play_index = -1;
	
	for (uint32 itrack = start; itrack < end; ++itrack) {
		const Track &track = tracklist[itrack];
		
		const char *album = get_metadata_string(track.metadata, METADATA_ALBUM);
		const char *artist = get_metadata_string(track.metadata, METADATA_ARTIST);
		const char *title = get_metadata_string(track.metadata, METADATA_TITLE);
		
		bool selected = tracklist.track_is_selected(itrack);
		bool playing = is_track_playing(track);
		
		if (filter_enabled && !filter->check(album, artist, title)) continue;
		
		ImGui::TableNextRow();
		
		if (jump_to_playing && (G.playing_track.metadata == track.metadata)) {
			ImGui::SetScrollHereY();
		}
		
		// Change cell color if this track is playing
		if (playing) {
			ImGui::TableSetBgColor(ImGuiTableBgTarget_RowBg0, get_theme_color(THEME_COLOR_PLAYING_INDICATOR));
			ImGui::PushStyleColor(ImGuiCol_Text, get_theme_color(THEME_COLOR_PLAYING_TEXT));
		}
		
		// ====== Album
		if (ImGui::TableNextColumn()) {
			ImGui::TextUnformatted(album);
		}
		
		// ====== Artist
		if (ImGui::TableNextColumn()) {
			ImGui::TextUnformatted(artist);
		}
		
		// ====== Title
		if (ImGui::TableNextColumn()) {
			
			if (ImGui::Selectable(get_metadata_string(track.metadata, METADATA_TITLE),
								  selected, ImGuiSelectableFlags_SpanAllColumns)) {
				if (!filter_enabled && (io.KeyMods & ImGuiMod_Shift)) tracklist.select_to(itrack);
				else tracklist.select(itrack);
			}
			
			// Pop cell color change
			
			// Prepare for drag and drop
			if (ImGui::BeginDragDropSource()) {
				Tracklist *payload = new Tracklist();
				
				if (!tracklist.track_is_selected(itrack)) tracklist.select(itrack);
				
				tracklist.copy_selection(payload);
				
				ImGui::SetDragDropPayload("TRACKS", &payload, sizeof(void*));
				ImGui::SetTooltip("%u tracks", payload->length());
				ImGui::EndDragDropSource();
			}
			
			if (ImGui::IsItemClicked(ImGuiMouseButton_Middle) || 
				(ImGui::IsItemClicked() && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left))) {
				play_index = itrack;
				log_debug("itrack = %d\n", play_index);
				tracklist.select(itrack);
			}
			
			if (ImGui::IsItemHovered() && ImGui::IsKeyPressed(ImGuiKey_Enter)) {
				play_index = itrack;
			}
		} else {
			if (playing) ImGui::PopStyleColor();
			continue;
		}
		
		if (ImGui::BeginPopupContextItem()) {
			if (playing) ImGui::PopStyleColor();
			
			if (!selected) tracklist.select(itrack);
			
			if (ImGui::BeginMenu("Add to playlist")) {
				int32 iplaylist = show_playlist_dropdown_selector();
				if (iplaylist != -1) {
					Tracklist &playlist = G.playlists[iplaylist];
					tracklist.copy_selection(&playlist);
					playlist.save_to_file();
				}
				ImGui::EndMenu();
			}
			
			if (editable && ImGui::MenuItem("Remove")) {
				tracklist.remove_selection();
				tracklist.save_to_file();
				tracklist.select(0);
			}
			
			if (queueable && ImGui::MenuItem("Add to queue")) {
				tracklist.copy_selection(&G.playlists[PLAYLIST_QUEUE]);
			}
			
			ImGui::EndPopup();
			
			if (playing) {
				ImGui::TableSetBgColor(ImGuiTableBgTarget_RowBg0, get_theme_color(THEME_COLOR_PLAYING_INDICATOR));
				ImGui::PushStyleColor(ImGuiCol_Text, get_theme_color(THEME_COLOR_PLAYING_TEXT));
			}
		}
		
		// ====== Duration
		if (ImGui::TableNextColumn()){
			const char *duration = get_metadata_string(track.metadata, METADATA_DURATION);
			ImGui::TextUnformatted(duration);
		}
		
		if (playing) ImGui::PopStyleColor();
		
	}
	
	return play_index;
}

static int32 show_track_list_gui(Tracklist& tracklist, int32 playlist_id, const Track_Filter *filter, bool jump_to_playing = false) {
	const ImGuiTableFlags table_flags =
		ImGuiTableFlags_BordersInner |
		ImGuiTableFlags_RowBg |
		ImGuiTableFlags_Resizable |
		ImGuiTableFlags_SizingFixedFit |
		ImGuiTableFlags_ScrollY |
		ImGuiTableFlags_Hideable;
	uint32 track_count = tracklist.length();
	int32 play_index = -1;
	bool editable = (playlist_id != PLAYLIST_LIBRARY) && (playlist_id >= 0);
	bool queueable = playlist_id != PLAYLIST_QUEUE;
	bool filter_enabled = filter && filter->enabled && filter->filter[0];
	//bool use_clipper = !filter_enabled;
	bool use_clipper = false;
	ImGuiIO &io = ImGui::GetIO();
	
	// Handle hotkeys
	if (ImGui::IsWindowFocused(ImGuiFocusedFlags_ChildWindows)){
		if (ImGui::IsKeyChordPressed(ImGuiKey_Q|ImGuiMod_Ctrl|ImGuiMod_Shift) && queueable) {
			tracklist.copy_selection(&G.playlists[PLAYLIST_QUEUE]);
		}
		else if (ImGui::IsKeyChordPressed(ImGuiKey_Q|ImGuiMod_Ctrl) && queueable) {
			G.playlists[PLAYLIST_QUEUE].clear();
			tracklist.copy_selection(&G.playlists[PLAYLIST_QUEUE]);
			if (G.shuffle_enabled) G.playlists[PLAYLIST_QUEUE].shuffle();
			play_track_at(PLAYLIST_QUEUE, 0);
		}
		
		if (ImGui::IsKeyChordPressed(ImGuiKey_A|ImGuiMod_Ctrl)) {
			tracklist.select(0);
			tracklist.select_to(tracklist.length() - 1);
		}
		
		if (ImGui::IsKeyPressed(ImGuiKey_KeypadDecimal) || ImGui::IsKeyPressed(ImGuiKey_Delete)) {
			tracklist.remove_selection();
			tracklist.save_to_file();
			tracklist.select(0);
		}
	}
	
	ImGuiListClipper clipper = ImGuiListClipper();
	if (use_clipper) clipper.Begin(tracklist.length());
	
	char table_id[192] = {};
	// Use the file path of the playlist as the table ID. This makes ImGui remember the column
	// sizing per playlist
	snprintf(table_id, sizeof(table_id)-1, "##%s", G.playlists[playlist_id].m_filename);
	if (ImGui::BeginTable(table_id, 4, table_flags)) {
		ImGui::TableSetupColumn("Album", 0, 200.f);
		ImGui::TableSetupColumn("Artist", 0, 200.f);
		ImGui::TableSetupColumn("Title", ImGuiTableColumnFlags_NoHide, 400.f);
		ImGui::TableSetupColumn("Duration", 0, 100.f);
		ImGui::TableSetupScrollFreeze(1, 1);

		ImGui::TableHeadersRow();
		ImGui::TableSetColumnIndex(0);
		ImGui::TableHeader("Album");
		ImGui::TableSetColumnIndex(1);
		ImGui::TableHeader("Artist");
		ImGui::TableSetColumnIndex(2);
		ImGui::TableHeader("Title");
		ImGui::TableSetColumnIndex(3);
		ImGui::TableHeader("Duration");
		
		if (use_clipper) while (clipper.Step()) {
			int32 i;
			i = show_track_list_range(tracklist, playlist_id, clipper.DisplayStart, clipper.DisplayEnd, filter, jump_to_playing);
			if (i != -1) play_index = i;
		}
		else {
			play_index = show_track_list_range(tracklist, playlist_id, 0, tracklist.length(), filter, jump_to_playing);
		}

		ImGui::EndTable();
	}

	return play_index;
}

static int32 show_album_grid_ui(const Auto_Array<Album>& albums) {
	uint32 album_count = albums.m_count;
	const ImGuiTableFlags table_flags =
		ImGuiTableFlags_ScrollY;
	
	int padding = 16;
	int column_count = (int)(ImGui::GetWindowWidth() / (128+(padding*2)));
	
	if (!column_count) return -1;
	
	ImGui::PushStyleVar(ImGuiStyleVar_CellPadding, ImVec2{(float)padding, (float)padding});
	
	if (ImGui::BeginTable("##album_table", column_count, table_flags)) {
		ImGui::TableNextRow();
		for (uint32 i = 0; i < album_count; ++i) {
			const Album& album = albums[i];
			const char *name = get_metadata_string(album.metadata, METADATA_ALBUM);
			bool hovered = false;
			bool play = false;
			
			ImGui::TableNextColumn();
			ImGui::Image((ImTextureID)album.thumbnail, ImVec2{128, 128});
			
			hovered |= ImGui::IsItemHovered();
			if (hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) play = true;
			
			play |= ImGui::Selectable(name);
			hovered |= ImGui::IsItemHovered();
			
			if (hovered) ImGui::SetTooltip("%s", name);
			if (play) {
				queue_tracklist(album.tracks);
				play_track_at(PLAYLIST_QUEUE, 0);
			}
		}
		ImGui::EndTable();
	}
	
	ImGui::PopStyleVar();
	
	return -1;
}

static void show_album_list_ui(const Auto_Array<Album>& albums) {
	uint32 album_count = albums.m_count;
	const ImGuiTableFlags table_flags =
		ImGuiTableFlags_ScrollY|ImGuiTableFlags_BordersInner|ImGuiTableFlags_Resizable|
		ImGuiTableFlags_SizingFixedFit|ImGuiTableFlags_RowBg|ImGuiTableFlags_NoHostExtendX;
	
	if (ImGui::BeginTable("##album_list", 3, table_flags)) {
		ImGui::TableHeadersRow();
		ImGui::TableSetColumnIndex(0);
		ImGui::TableHeader("Artist");
		ImGui::TableSetColumnIndex(1);
		ImGui::TableHeader("Album");
		ImGui::TableSetColumnIndex(2);
		ImGui::TableHeader("No. Tracks");
		
		for (uint32 i = 0; i < album_count; ++i) {
			ImGui::TableNextRow();
			const Album& album = albums[i];
			const char *artist = get_metadata_string(album.metadata, METADATA_ARTIST);
			const char *name = get_metadata_string(album.metadata, METADATA_ALBUM);
			
			ImGui::TableSetColumnIndex(0);
			ImGui::TextUnformatted(artist);
			
			ImGui::TableSetColumnIndex(1);
			if (ImGui::Selectable(name, false, ImGuiSelectableFlags_SpanAllColumns)) {
				queue_tracklist(album.tracks);
				play_track_at(PLAYLIST_QUEUE, 0);
			}
			
			ImGui::TableSetColumnIndex(2);
			ImGui::Text("%u", album.tracks.length());
		}
		
		ImGui::EndTable();
	}
}

static bool add_playlist(const char *path) {
	Tracklist tracklist = {};
	log_debug("Load playlist \"%s\"\n", path);
	tracklist.load_from_file(path);
	G.playlists.append(tracklist);
	return true;
}

static void clean_up() {
	log_debug("Cleaning up UI...\n");
	save_metadata_cache();
	G.playlists[PLAYLIST_LIBRARY].save_to_file(".\\library");
	G.playlists[PLAYLIST_QUEUE].save_to_file(".\\queue");
}

void init_ui() {
	set_default_theme();
	START_TIMER(load_metadata, "Load metadata cache");
	load_metadata_cache();
	STOP_TIMER(load_metadata);
	
	refresh_layouts();
	install_imgui_settings_handler();
	
	if (!file_exists(".\\layouts")) {
		create_directory(".\\layouts");
	}
	
	if (!file_exists(".\\imgui.ini")) {
		ImGui::LoadIniSettingsFromMemory(DEFAULT_LAYOUT_INI);
	}
	
	// Library and queue
	{
		Tracklist library = {};
		Tracklist queue = {};
		
		START_TIMER(load_library, "Load library");
		if (file_exists(".\\library")) {
			library.load_from_file(".\\library");
		}
		if (file_exists(".\\queue")) {
			queue.load_from_file(".\\queue");
		}
		
		strncpy(library.name, "Library", sizeof(library.name)-1);
		strncpy(queue.name, "Queue", sizeof(queue.name)-1);
		library.save_to_file(".\\library");
		queue.save_to_file(".\\queue");
		STOP_TIMER(load_library);
		
		G.playlists.append(library);
		G.playlists.append(queue);
	}
	
	START_TIMER(load_playlists, "Load playlists");
	for_each_file_in_directory(L"playlists", &add_playlist);
	if (!file_exists("playlists")) {
		create_directory("playlists");
	}
	sort_playlists();
	STOP_TIMER(load_playlists);
	
	load_stats();
	
	G.renaming_playlist = -1;
	G.selected_playlist = PLAYLIST_LIBRARY;
	G.queued_playlist = -1;
	atexit(&clean_up);
}

void ui_add_to_library(Track &track) {
	if (G.playlists.m_count > PLAYLIST_LIBRARY) {
		G.playlists[PLAYLIST_LIBRARY].add(track);
	}
}

static void queue_tracklist(const Tracklist &tracklist) {
	G.playlists[PLAYLIST_QUEUE].clear();
	tracklist.copy(&G.playlists[PLAYLIST_QUEUE]);
	if (G.shuffle_enabled) G.playlists[PLAYLIST_QUEUE].shuffle();
}

static void queue_playlist(int32 index) {
	const Tracklist &tracklist = G.playlists[index];
	queue_tracklist(tracklist);
}

static void create_playlist() {
	Tracklist list = {};
	G.renaming_playlist = G.playlists.append(list);
	G.playlist_order.append(G.renaming_playlist);
}

static bool add_from_file_select_dialog_callback(const char *path) {
	Tracklist &playlist = G.playlists[G.selected_playlist];
	playlist.add(path);
	return true;
}

static void add_from_file_select_dialog() {
	for_each_file_from_dialog(&add_from_file_select_dialog_callback, FILE_DATA_TYPE_MUSIC);
	G.playlists[G.selected_playlist].save_to_file();
}

void ui_accept_drag_drop_to_tracklist(const Track_Drag_Drop_Payload *payload, Tracklist &tracklist) {
	char path[512];
	if (G.selected_playlist == -1) return;
	
	for (uint32 i = 0; i < payload->paths.length(); ++i) {
		payload->path_pool.get(payload->paths[i], path, 512);
		log_debug("%s\n", path);
		tracklist.add(path);
	}
}

void ui_accept_drag_drop(const Track_Drag_Drop_Payload *payload) {
	Tracklist &tracklist = G.playlists[G.selected_playlist];
	ui_accept_drag_drop_to_tracklist(payload, tracklist);
	tracklist.save_to_file();
	if (G.selected_playlist == G.queued_playlist) {
		queue_playlist(G.selected_playlist);
	}
}

static void show_track_info_ui() {
	if (G.playing_track.metadata) {
		Metadata_Ref metadata = G.playing_track.metadata;
		const char *title = get_metadata_string(metadata, METADATA_TITLE);
		const char *artist = get_metadata_string(metadata, METADATA_ARTIST);
		const char *album = get_metadata_string(metadata, METADATA_ALBUM);
		const char *duration = get_metadata_string(metadata, METADATA_DURATION);

		ImGui::Text("Title: %s\nArtist: %s\nAlbum:%s\nDuration: %s\n", title, artist, album, duration);
	}
}

static bool show_navigation_ui() {
	ImVec2 window_size = ImGui::GetWindowSize();
	const ImGuiStyle& style = ImGui::GetStyle();
	float image_dim = window_size.x - style.WindowPadding.x*2.f;
	if (image_dim > FLT_EPSILON) {
		if (G.thumbnail) {
			ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(0, 0));
			ImGui::ImageButton("##playing_track_thumbnail", G.thumbnail, ImVec2{image_dim, image_dim});
			ImGui::PopStyleVar();
		} else ImGui::InvisibleButton("##missing_thumbnail", ImVec2{image_dim, image_dim});
		if (G.playing_track.metadata && ImGui::BeginPopupContextItem()) {
			if (ImGui::BeginMenu("Add to playlist")) {
				int32 iplaylist = show_playlist_dropdown_selector();
				if (iplaylist >= 0) {
					Tracklist& playlist = G.playlists[iplaylist];
					playlist.add(G.playing_track, false);
					playlist.save_to_file();
				}
				ImGui::EndMenu();
			}
			ImGui::EndPopup();
		}
	}

	// Library and queue
	if (ImGui::BeginTable("##navigation", 1, ImGuiTableFlags_BordersInner)) {
		ImGui::TableSetupColumn("##names");
		
		ImGui::TableNextRow();
		ImGui::TableSetColumnIndex(0);
		if (ImGui::Selectable("Albums##albums", G.main_view == MAIN_VIEW_ALBUMS)) {
			G.main_view = MAIN_VIEW_ALBUMS;
			G.selected_playlist = PLAYLIST_LIBRARY;
		}
		
		ImGui::TableNextRow();
		ImGui::TableSetColumnIndex(0);
		if (ImGui::Selectable("Library##library", G.selected_playlist == PLAYLIST_LIBRARY && G.main_view == MAIN_VIEW_TRACKS)) {
			G.selected_playlist = PLAYLIST_LIBRARY;
			G.main_view = MAIN_VIEW_TRACKS;
		}
		
		if (ImGui::IsItemClicked(ImGuiMouseButton_Middle) || 
			(ImGui::IsItemClicked() && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left))) {
			G.selected_playlist = PLAYLIST_LIBRARY;
			play_track_at(PLAYLIST_LIBRARY, 0);
		}
		ImGui::SetItemTooltip("%u tracks", G.playlists[PLAYLIST_LIBRARY].length());
		
		ImGui::TableNextRow();
		ImGui::TableSetColumnIndex(0);
		if (ImGui::Selectable("Queue##queue", G.selected_playlist == PLAYLIST_QUEUE && G.main_view == MAIN_VIEW_TRACKS)) {
			G.selected_playlist = PLAYLIST_QUEUE;
			G.main_view = MAIN_VIEW_TRACKS;
		}
		ImGui::SetItemTooltip("%u tracks", G.playlists[PLAYLIST_QUEUE].length());
		
		ImGui::EndTable();
	}
	
	
	ImGui::SeparatorText("Playlists");
	
	ImGuiTableFlags table_flags = ImGuiTableFlags_BordersInner|
		ImGuiTableFlags_ScrollY;
	
	// Playlist list
	ImVec2 playlist_list_size = 
		ImVec2(0, ImGui::GetContentRegionAvail().y - (ImGui::GetTextLineHeight()*2.f));
	if (ImGui::BeginTable("##playlists", 2, table_flags, playlist_list_size)) {
		ImGui::TableSetupColumn("##names", ImGuiTableColumnFlags_WidthStretch, 0.8f);
		ImGui::TableSetupColumn("##sizes", ImGuiTableColumnFlags_WidthStretch, 0.2f);
		uint32 playlist_count = G.playlists.length();
		static int deleting_playlist;
		ImGuiID delete_confirmation_popup_id = ImGui::GetID("##delete_confirmation");
		
		// Delete playlist?
		if (ImGui::BeginPopup("##delete_confirmation")) {
			assert(deleting_playlist >= PLAYLIST_USER);
			Tracklist &playlist = G.playlists[deleting_playlist];
			ImGui::Text("Delete playlist \"%s\"? (Cannot be undone)", G.playlists[deleting_playlist].name);
			if (ImGui::Button("Delete")) {
				playlist.delete_file();
				G.playlists.remove_range(deleting_playlist, deleting_playlist);
				if (deleting_playlist == G.selected_playlist) G.selected_playlist = -1;
				if (deleting_playlist == G.queued_playlist) G.queued_playlist = -1;
				sort_playlists();
				ImGui::CloseCurrentPopup();
			}
			ImGui::SameLine();
			if (ImGui::Button("Cancel")) {
				ImGui::CloseCurrentPopup();
			}
			ImGui::EndPopup();
		}
		
		// Show list of user playlists
		for (uint32 order = 0; order < G.playlist_order.m_count; ++order) {
			uint32 iplaylist = G.playlist_order[order];
			if (iplaylist < PLAYLIST_USER || iplaylist >= G.playlists.m_count) continue;
			Tracklist &playlist = G.playlists[iplaylist];
			ImGui::TableNextRow();
			ImGui::TableSetColumnIndex(0);
			// Rename playlist
			if (G.renaming_playlist == iplaylist) {
				bool commit = false;
				ImGui::SetWindowFocus();
				ImGui::SetKeyboardFocusHere();
				
				commit |= ImGui::InputText("##playlist_name", playlist.name, 
										   sizeof(playlist.name), ImGuiInputTextFlags_EnterReturnsTrue);
				if (commit) {
					// Store the name of the playlist so we can find its new index in the playlist array
					char name[sizeof(playlist.name)+1];
					name[sizeof(playlist.name)] = 0;
					strncpy(name, playlist.name, sizeof(playlist.name));
					
					G.renaming_playlist = -1;
					playlist.save_to_file();
					sort_playlists();
					
					// Find new index of playlist and select it
					for (uint32 i = PLAYLIST_USER; i < G.playlists.m_count; ++i) {
						if (!strcmp(G.playlists[i].name, name)) {
							G.selected_playlist = i;
							break;
						}
					}
				}
			}
			else {
				char name_id[128];					
				bool playing = (iplaylist == G.queued_playlist);
				snprintf(name_id, sizeof(name_id), "%s##%s", playlist.name, playlist.get_filename());
				
				bool selected = G.selected_playlist == iplaylist && G.main_view == MAIN_VIEW_TRACKS;
				
				if (playing) {
					ImGui::TableSetBgColor(ImGuiTableBgTarget_RowBg0,
										   get_theme_color(THEME_COLOR_PLAYING_INDICATOR));
					ImGui::PushStyleColor(ImGuiCol_Text, get_theme_color(THEME_COLOR_PLAYING_TEXT));
				}
				
				if (ImGui::Selectable(name_id, selected, ImGuiSelectableFlags_SpanAllColumns)) {
					G.selected_playlist = iplaylist;
					G.main_view = MAIN_VIEW_TRACKS;
				}
				
				if (selected && ImGui::IsKeyPressed(ImGuiKey_F2)) {
					G.renaming_playlist = iplaylist;
				}
				
				if (playing) ImGui::PopStyleColor();
				
				ImGui::SetItemTooltip("%u tracks", playlist.length());
				
				if (ImGui::IsItemClicked(ImGuiMouseButton_Middle) || 
					(ImGui::IsItemClicked() && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left))) {
					G.selected_playlist = iplaylist;
					play_track_at(iplaylist, 0);
				}
				
				// Accept incoming track drag and drop
				if (ImGui::BeginDragDropTarget()) {
					const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("TRACKS");
					if (payload) {
						Tracklist *track_payload = *(Tracklist **)payload->Data;
						track_payload->copy(&playlist);
						delete track_payload;
						playlist.save_to_file();
						if (iplaylist == G.queued_playlist) {
							queue_playlist(iplaylist);
						}
					}
					ImGui::EndDragDropTarget();
				}
				
				// Right click context menu
				if (ImGui::BeginPopupContextItem()) {
					if (ImGui::MenuItem("Rename")) {
						G.renaming_playlist = iplaylist;
					}
					if (ImGui::MenuItem("Delete")) {
						deleting_playlist = iplaylist;
						ImGui::OpenPopup(delete_confirmation_popup_id);
					}
					if (ImGui::BeginMenu("Sort by")) {
						if (ImGui::MenuItem("Album")) {
							playlist.sort(METADATA_ALBUM);
							playlist.save_to_file();
							if (iplaylist == G.queued_playlist) queue_playlist(iplaylist);
						}
						if (ImGui::MenuItem("Artist")) {
							playlist.sort(METADATA_ARTIST);
							playlist.save_to_file();
							if (iplaylist == G.queued_playlist) queue_playlist(iplaylist);
						}
						if (ImGui::MenuItem("Title")) {
							playlist.sort(METADATA_TITLE);
							playlist.save_to_file();
							if (iplaylist == G.queued_playlist) queue_playlist(iplaylist);
						}
						ImGui::EndMenu();
					}
					ImGui::EndPopup();
				}
			}
			
			ImGui::TableSetColumnIndex(1);
			ImGui::TextDisabled("%u", playlist.length());
		}
		ImGui::EndTable();
	}
	
	ImGui::Separator();
	if (ImGui::Selectable("+ New playlist...")) {
		create_playlist();
	}
	
	return true;
}

static bool show_control_panel_ui() {
	const ImGuiStyle &style = ImGui::GetStyle();
	const int64 playback_position = stream_get_pos();
	const int64 playback_duration = stream_get_duration();
	
	// Shuffle
	ImGui::SameLine();
	if (small_selectable(u8"\xf074", &G.shuffle_enabled)) {
		if (G.shuffle_enabled) G.playlists[PLAYLIST_QUEUE].shuffle();
		else if ((G.queued_playlist != -1) && (G.queued_playlist != PLAYLIST_QUEUE)) {
			G.playlists[PLAYLIST_QUEUE].clear();
			G.playlists[G.queued_playlist].copy(&G.playlists[PLAYLIST_QUEUE]);
		}
	}
	
	// Previous track
	ImGui::SameLine();
	if (small_selectable(u8"\xf048")) {
		goto_previous_track();
	}
	
	// Play/pause
	ImGui::SameLine();
	if (small_selectable(G.state == STREAM_STATE_PLAYING ? u8"\xf04c" : u8"\xf04b")) {
		if (G.state != STREAM_STATE_STOPPED) stream_toggle_playing();
		else {
			play_track_at(PLAYLIST_QUEUE, 0);
		}
	}
	
	// Next track
	ImGui::SameLine();
	if (small_selectable(u8"\xf051")) {
		goto_next_track();
	}
	
	if (G.state != STREAM_STATE_STOPPED) {
		int64 new_pos;
		const Track &track = G.playing_track;
		const char *title = get_metadata_string(track.metadata, METADATA_TITLE);
		const char *artist = get_metadata_string(track.metadata, METADATA_ARTIST);
		ImVec2 size = ImGui::GetContentRegionAvail();
		
		if (ImGui::BeginPopupContextWindow()) {
			if (ImGui::BeginMenu("Add to playlist")) {
				int32 iplaylist = show_playlist_dropdown_selector();
				if (iplaylist != -1) {
					Tracklist &playlist = G.playlists[iplaylist];
					playlist.add(track);
					playlist.save_to_file();
				}
				ImGui::EndMenu();
			}
			
			ImGui::EndPopup();
		}
		
		// Timer
		ImGui::SameLine();
		{
			char pos[64];
			char duration[64];
			
			format_time(playback_position, pos, 64);
			format_time(playback_duration, duration, 64);
			
			ImGui::Text("%s/%s", pos, duration);
		}
		
		// Draw artist - title centered in the panel
		ImGui::SameLine();
		{
			char pt[256];
			ImVec2 text_size;
			ImVec2 cursor = ImGui::GetCursorPos();
			
			snprintf(pt, 256, "%s - %s", artist, title);
			text_size = ImGui::CalcTextSize(pt);
			cursor.x = (size.x / 2) - (text_size.x / 2) - style.ItemInnerSpacing.x;
			ImGui::SetCursorPos(cursor);
			ImGui::TextUnformatted(pt);
			
			
		}
		
		// Volume slider
		ImGui::SameLine();
		{
			const char *icon = u8"\xf028";
			ImVec2 icon_size = ImGui::CalcTextSize(icon);
			float volume = stream_get_volume();
			ImVec2 cursor = ImGui::GetCursorPos();
			float width = 90.f;
			cursor.x = size.x - width - (style.ItemInnerSpacing.x*2.f) - (style.WindowPadding.x*2.f) - icon_size.x;
			ImGui::SetCursorPos(cursor);
			
			if (circle_handle_slider(icon, &volume, 0.f, 1.f, width)) {
				stream_set_volume(volume);
				ImGui::SetTooltip("%d%%", (int)(100.f * volume));
			}
		}
	
		ImVec2 remaining_size = ImGui::GetContentRegionAvail();
		// Seek bar
		if (remaining_size.y > 2.f) {
			if (seek_slider("##seek", playback_position, playback_duration, 
							&new_pos, remaining_size.y, G.waveform_image)) {
				stream_seek(new_pos*1000);
			}
		} 
	}
	
	return true;
}

static int32 show_layout_selector_ui() {
	if (G.layouts.m_count) {
		for (uint32 i = 0; i < G.layouts.m_count; ++i) {
			if (ImGui::Selectable(G.layouts[i].name)) {
				return i;
			}
		}
	} else {
		ImGui::TextDisabled("No layouts found");
	}
	return -1;
}

static int32 get_layout_from_name(const char *name) {
	for (uint32 i = 0; i < G.layouts.m_count; ++i) {
		if (!strcmp(G.layouts[i].name, name)) {
			return i;
		}
	}
	
	return -1;
}

static const char *get_layout_path(int32 index) {
	return lazy_format("layouts/%s.ini", G.layouts[index].name);
}

static const char *get_layout_path(const Layout& layout) {
	return lazy_format("layouts/%s.ini", layout.name);
}

bool show_ui() {
	ImGuiIO &io = ImGui::GetIO();
	ImGuiStyle& style = ImGui::GetStyle();
	bool running = true;
	bool jump_to_playing = false;
	static bool show_hotkeys = false;
	static bool show_about = false;
	
	G.state = stream_get_state();

	//=============================================================================================
	// Handle hotkeys
	//=============================================================================================
	{
		bool focused =
			ImGui::IsAnyItemActive() ||
			ImGui::IsAnyItemFocused();
		
		if (!focused) {
			if (ImGui::IsKeyChordPressed(ImGuiKey_Space | ImGuiMod_Ctrl | ImGuiMod_Shift)) {
				jump_to_playing = true;
				G.selected_playlist = G.queued_playlist;
			}
			else if (ImGui::IsKeyChordPressed(ImGuiKey_Space | ImGuiMod_Ctrl)) {
				jump_to_playing = true;
			}
			else if (ImGui::IsKeyPressed(ImGuiKey_Space)) {
				stream_toggle_playing();
			}
		}
	}
	
	//=============================================================================================
	// Main menu
	//=============================================================================================
	float menu_bar_height;
	if (ImGui::BeginMainMenuBar()) {
		if (ImGui::BeginMenu("File")) {
			bool playlist_available = (G.selected_playlist != -1) 
				&& G.playlists.length() && (G.selected_playlist != PLAYLIST_QUEUE);
			
			// =========================================
			// Only when playlist is available
			ImGui::BeginDisabled(!playlist_available);
			if (ImGui::MenuItem("Add files")) {
				add_from_file_select_dialog();
				if (G.selected_playlist == G.queued_playlist) {
					queue_playlist(G.selected_playlist);
				}
			}
			

			if (ImGui::MenuItem("Add folder")) {
				wchar_t folder[512];
				if (select_folder_dialog(folder, 512)) {
					for_each_file_in_directory(folder, &add_from_file_select_dialog_callback);
					G.playlists[G.selected_playlist].save_to_file();
					if (G.selected_playlist == G.queued_playlist) {
						queue_playlist(G.selected_playlist);
					}
				}
			}
			ImGui::EndDisabled();
			// =========================================
			
			if (ImGui::MenuItem("Create playlist")) {
				create_playlist();
			}
			
			if (ImGui::MenuItem("Exit to tray")) {
				close_window_to_tray();
			}
			
			if (ImGui::MenuItem("Exit")) {
				running = false;
			}

			ImGui::EndMenu();
		}
		menu_bar_height = ImGui::GetItemRectSize().y;
		
		if (ImGui::BeginMenu("Edit")) {
			if (ImGui::MenuItem("Edit theme")) {
				ui_show_window(UI_WINDOW_THEME_EDITOR);
				ui_bring_window_to_front(UI_WINDOW_THEME_EDITOR);
			}
			if (ImGui::MenuItem("Preferences")) {
				ui_show_window(UI_WINDOW_PREFERENCES);
				ui_bring_window_to_front(UI_WINDOW_PREFERENCES);
			}
			ImGui::EndMenu();
		}
		
		if (ImGui::BeginMenu("View")) {
			if (ImGui::MenuItem("Show missing tracks")) {
				ui_show_window(UI_WINDOW_MISSING_TRACKS);
				ui_bring_window_to_front(UI_WINDOW_MISSING_TRACKS);
			}
			if (ImGui::MenuItem("Playback statistics")) {
				ui_show_window(UI_WINDOW_PLAYBACK_STATS);
				ui_bring_window_to_front(UI_WINDOW_PLAYBACK_STATS);
			}
			ImGui::EndMenu();
		}
		
		if (ImGui::BeginMenu("Layout")) {
			static char layout_name[512];
			
			if (ImGui::MenuItem("Refresh layouts")) {
				refresh_layouts();
			}
			
			if (ImGui::MenuItem("Reset layout")) {
				ImGui::LoadIniSettingsFromMemory(DEFAULT_LAYOUT_INI);
			}
			
			if (ImGui::BeginMenu("Load layout")) {
				int32 layout = show_layout_selector_ui();
				if (layout >= 0) {
					ImGui::LoadIniSettingsFromDisk(get_layout_path(layout));
				}
				ImGui::EndMenu();
			}
			
			if (ImGui::BeginMenu("Save layout")) {
				int32 layout = show_layout_selector_ui();
				if (layout >= 0) {
					bool confirm = show_confirmation_dialog("Overwrite Layout",
															"Do you want to overwrite layout \"%s\"?",
															G.layouts[layout].name);
					if (confirm) ImGui::SaveIniSettingsToDisk(get_layout_path(layout));
				}
				ImGui::EndMenu();
			}
			
			if (ImGui::BeginMenu("Save as")) {
				static Layout new_layout = {};
				bool commit = ImGui::InputText("Name", new_layout.name, 
											   sizeof(new_layout.name),
											   ImGuiInputTextFlags_EnterReturnsTrue);
				commit |= ImGui::MenuItem("Save");
				
				if (commit) {
					if (new_layout.name[0] == 0) {
						commit = false;
						show_message_box(MESSAGE_BOX_WARNING, "Must enter a name");
					} else if (get_layout_from_name(new_layout.name) >= 0) {
						// Layout already exists, ask for overwrite
						commit = show_confirmation_dialog("Overwrite Layout", 
														  "Overwrite existing layout \"%s\"?",
														  new_layout.name);	
					}
					
					if (commit) {
						ImGui::SaveIniSettingsToDisk(get_layout_path(new_layout));
						G.layouts.append(new_layout);
					}
					
					memset(new_layout.name, 0, sizeof(new_layout.name));
				}
				
				ImGui::EndMenu();
			}
			
			ImGui::EndMenu();
		}
		
		if (ImGui::BeginMenu("Show")) {
			for (uint32 i = 0; i < UI_WINDOW__COUNT; ++i) {
				if (ImGui::MenuItem(ui_get_window_name((UI_Window)i), NULL, G.windows[i].show)) {
					ui_bring_window_to_front((UI_Window)i);
				}
			}
			ImGui::EndMenu();
		}
		
		if (ImGui::BeginMenu("Help")) {
			if (ImGui::MenuItem("Hotkeys")) {
				show_hotkeys = true;
			}
			if (ImGui::MenuItem("About")) {
				show_about = true;
			}
			ImGui::EndMenu();
		}
		
		const float window_button_width = ImGui::GetWindowHeight();
		ImGui::SetCursorPosX(io.DisplaySize.x - (window_button_width*3.f) - 1.f);
		
		ImGui::EndMainMenuBar();
	}

	{
		ImGui::SetNextWindowPos(ImVec2(-style.WindowPadding.x, menu_bar_height - style.WindowPadding.y));
		ImGui::SetNextWindowSize(ImVec2(io.DisplaySize.x + (style.WindowPadding.x*2.f),
								io.DisplaySize.y - menu_bar_height + (style.WindowPadding.y*2.f)));
		ImGuiWindowFlags window_flags =
			ImGuiWindowFlags_NoBringToFrontOnFocus|
			ImGuiWindowFlags_NoNavFocus|
			ImGuiWindowFlags_NoBackground|
			ImGuiWindowFlags_NoDecoration;
		bool showing = ImGui::Begin("Main Window", NULL, window_flags);
		ImGuiDockNodeFlags dockspace_flags =
			ImGuiDockNodeFlags_PassthruCentralNode;
		if (!showing) dockspace_flags |= ImGuiDockNodeFlags_KeepAliveOnly;
		ImGui::DockSpace(ImGui::GetID("MainDockSpace"), ImVec2(0, 0), dockspace_flags);
		ImGui::End();
	}

	if (ImGui::Begin("Navigation", NULL, 0)) {
		show_navigation_ui();
	} ImGui::End();

	//=============================================================================================
	// Control panel
	//=============================================================================================
	if (ImGui::Begin("Control Panel", NULL, 0)) {
		show_control_panel_ui();
	} ImGui::End();

	if (ImGui::Begin("Track View", NULL, 0)) {
		//=============================================================================================
		// Track list
		//=============================================================================================
		if (G.main_view == MAIN_VIEW_ALBUMS) {
			const Auto_Array<Album>& albums = get_albums();
			show_album_grid_ui(albums);
		}
		else if (G.selected_playlist != -1) {
			Tracklist &playlist = G.playlists[G.selected_playlist];
			static char filter_text[128];
			static Track_Filter filter;
			filter.add(TRACK_FILTER_ALBUM);
			filter.add(TRACK_FILTER_ARTIST);
			filter.add(TRACK_FILTER_TITLE);
			filter.filter = filter_text;
			
			const char *playlist_name = playlist.name[0] != 0 ? playlist.name : "<untitled>";
			char window_title[512];
			snprintf(window_title, 512, "%s [%u tracks]\n", playlist_name, playlist.length());
			
			if (ImGui::InputTextWithHint("##filter", "Filter", filter_text, 
						sizeof(filter_text), ImGuiInputTextFlags_EnterReturnsTrue)) {
				G.search_results.clear();
				if (filter.enabled && filter.filter[0]) {
					playlist.copy_with_filter(&G.search_results, &filter);
					ui_show_window(UI_WINDOW_SEARCH_RESULTS);
					ui_bring_window_to_front(UI_WINDOW_SEARCH_RESULTS);
				}
			}
			
			// Show sort-by dropdown if we aren't looking at the queue
			if (G.selected_playlist != PLAYLIST_QUEUE) {
				ImGui::SameLine();
				if (ImGui::BeginCombo("##sort", "Sort by", ImGuiComboFlags_WidthFitPreview)) {
					if (ImGui::Selectable("Album")) {
						playlist.sort(METADATA_ALBUM);
						playlist.save_to_file();
						if (G.selected_playlist == G.queued_playlist) 
							queue_playlist(G.selected_playlist);
					}
					if (ImGui::Selectable("Artist")) {
						playlist.sort(METADATA_ARTIST);
						playlist.save_to_file();
						if (G.selected_playlist == G.queued_playlist) 
							queue_playlist(G.selected_playlist);
					}
					if (ImGui::Selectable("Title")) {
						playlist.sort(METADATA_TITLE);
						playlist.save_to_file();
						if (G.selected_playlist == G.queued_playlist) 
							queue_playlist(G.selected_playlist);
					}
					ImGui::EndCombo();
				}
			}
			
			int32 play_index = show_track_list_gui(playlist, G.selected_playlist, &filter, jump_to_playing);
			if (play_index >= 0) {
				play_track_at(G.selected_playlist, play_index, true);
			}
		}
	} ImGui::End();
	
	if (show_hotkeys) {
		if (ImGui::Begin("Hotkeys", &show_hotkeys)) {
			show_hotkey_gui();
		}
		ImGui::End();
	}
	
	if (show_about) {
		if (ImGui::Begin("About", &show_about)) {
			show_about_gui();
		}
		ImGui::End();
	}
	
	for (uint32 i = 0; i < UI_WINDOW__COUNT; ++i) {
		UI_Window window_id = (UI_Window)i;
		Optional_Window& window = G.windows[i];
		ImGuiWindowFlags flags = ImGuiWindowFlags_NoFocusOnAppearing;
		ImVec2 default_size = ImVec2(500, 500);
		
		if (!window.show) continue;
		const char *title = ui_get_window_name(window_id);
		if (window.bring_to_front) {
			ImGui::SetNextWindowFocus();
			window.bring_to_front = false;
		}
		
		if (window_id == UI_WINDOW_THEME_EDITOR && G.dirty_theme)
			flags |= ImGuiWindowFlags_UnsavedDocument;
		
		ImGui::SetNextWindowSize(default_size, ImGuiCond_Once);
		if (ImGui::Begin(title, &window.show, flags)) {
			switch (window_id) {
				case UI_WINDOW_THEME_EDITOR:
				G.dirty_theme = show_theme_editor_gui();
				break;
				case UI_WINDOW_PREFERENCES:
				show_config_editor_gui();
				break;
				case UI_WINDOW_PLAYBACK_STATS:
				show_playback_stats_gui();
				break;
				case UI_WINDOW_MISSING_TRACKS:
				show_track_list_missing_tracks_ui(G.playlists[G.selected_playlist]);
				break;
				case UI_WINDOW_SEARCH_RESULTS: {
					int32 play_track = show_track_list_gui(G.search_results, -1, NULL);
					if (play_track >= 0) {
						queue_tracklist(G.search_results);
						play_track_at(PLAYLIST_QUEUE, 0);
					}
					break;
				}
				case UI_WINDOW_ALBUM_LIST:
				show_album_list_ui(get_albums());
				break;
				case UI_WINDOW__COUNT: break;
			}
		}
		ImGui::End();
	}
	
	return running;
}

void ui_set_thumbnail(void *texture) {
	G.thumbnail = (ImTextureID)texture;
}

void ui_set_waveform_image(void *texture) {
	G.waveform_image = (ImTextureID)texture;
}

void ui_handle_hotkey(uintptr_t hotkey) {
	switch (hotkey) {
	case GLOBAL_HOTKEY_NEXT_TRACK: goto_next_track(); break;
	case GLOBAL_HOTKEY_PREVIOUS_TRACK: goto_previous_track(); break;
	case GLOBAL_HOTKEY_TOGGLE_PLAYBACK: stream_toggle_playing(); break;
	}
}

static void show_config_editor_gui() {
	Config& config = g_config;
	bool apply = false;
	bool need_save = false;
	
	// Theme
	if (ImGui::BeginCombo("Theme", config.theme)) {
		const char *sel = show_theme_selector_gui();
		if (sel) {
			strncpy(config.theme, sel, sizeof(config.theme)-1);
			apply = true;
		}
		ImGui::EndCombo();
	}
	
	// Close policy
	{
		const char *close_policy_names[CLOSE_POLICY__COUNT];
		close_policy_names[CLOSE_POLICY_QUERY] = "Always ask";
		close_policy_names[CLOSE_POLICY_EXIT] = "Quit";
		close_policy_names[CLOSE_POLICY_EXIT_TO_TRAY] = "Minimize to tray";
		
		if (ImGui::BeginCombo("Close policy", close_policy_names[config.close_policy])) {
			for (int i = 0; i < CLOSE_POLICY__COUNT; ++i) {
				if (ImGui::Selectable(close_policy_names[i])) {
					config.close_policy = (Close_Policy)i;
					need_save = true;
				}
			}
			ImGui::EndCombo();
		}
	}
	ImGui::SetItemTooltip("What to do when closing the main window");
	
	// Glyph ranges
	ImGui::SeparatorText("Included language characters");
	ImGui::SetItemTooltip("Load characters for these languages from fonts if supported.");
	{
		USE_GLYPH_RANGE_NAMES(range_names);
		
		for (int i = 0; i < GLYPH_RANGE__COUNT; ++i) {
			apply |= ImGui::Checkbox(range_names[i], &config.include_glyphs[i]);
		}
	}
	
	// Thumbnail sizes
	if (ImGui::InputInt("Thumbnail size", &config.thumbnail_size)) {
		config.thumbnail_size = iclamp(config.thumbnail_size, MIN_THUMBNAIL_SIZE, MAX_THUMBNAIL_SIZE);
		need_save = true;
	}
	ImGui::SetItemTooltip("Size of album art for current track");
	
	if (ImGui::InputInt("Preview thumbnail size", &config.preview_thumbnail_size)) {
		config.thumbnail_size = iclamp(config.thumbnail_size, 
									   MIN_PREVIEW_THUMBNAIL_SIZE, MAX_PREVIEW_THUMBNAIL_SIZE);
		need_save = true;
	}
	ImGui::SetItemTooltip("Size of album art in albums view. Increasing this will increase memory usage"
						  " (Requires restart)");

	if (ImGui::BeginCombo("Waveform Horiz. Resolution", lazy_format("%d", 1<<g_config.waveform_height_power))) {
		for (int i = MIN_WAVEFORM_HEIGHT_POWER; i <= MAX_WAVEFORM_HEIGHT_POWER; ++i) {
			if (ImGui::Selectable(lazy_format("%d", 1<<i), g_config.waveform_height_power == i)) {
				g_config.waveform_height_power = i;
				need_save = true;
			}
		}
		ImGui::EndCombo();
	}

	if (ImGui::BeginCombo("Waveform Vert. Resolution", lazy_format("%d", 1<<g_config.waveform_width_power))) {
		for (int i = MIN_WAVEFORM_WIDTH_POWER; i <= MAX_WAVEFORM_WIDTH_POWER; ++i) {
			if (ImGui::Selectable(lazy_format("%d", 1<<i), g_config.waveform_width_power == i)) {
				g_config.waveform_width_power = i;
				need_save = true;
			}
		}
		ImGui::EndCombo();
	}
	
	ImGui::SeparatorText("Font");
	{
		char *font_path = get_font_path_buffer();
		int font_path_size = get_font_path_buffer_size();
		
		ImGui::InputText("Font", font_path, font_path_size);
		ImGui::SameLine();
		if (ImGui::Button("Browse##font")) {
			if (select_file_dialog(font_path, font_path_size)) {
				set_font(NULL);
			}
		}
		
		int font_size = get_font_size();
		if (ImGui::InputInt("Font size", &font_size)) {
			set_font_size(font_size);
			need_save = true;
		}
		
		int icon_size = get_icon_font_size();
		if (ImGui::InputInt("Icon size", &icon_size)) {
			set_icon_font_size(icon_size);
			need_save = true;
		}
		
		if (ImGui::Button("Apply")) set_font(NULL);
	}
	
	const char *background_path = g_config.background_path;
	ImGui::SeparatorText("Background");
	{
		ImGui::Text("Background Image: %s", background_path[0] ? background_path : "<none>");
		if (ImGui::Button("Browse##background")) {
			char buffer[512];
			if (select_file_dialog(buffer, sizeof(buffer))) {
				load_background_image(buffer);
				need_save = true;
			}
		}
		ImGui::SameLine();
		if (ImGui::Button("Remove")) {
			load_background_image(NULL);
			need_save = true;
		}
	}
	
	need_save |= apply;
	if (apply) apply_config();
	if (need_save) save_config();
}

static void show_hotkey_gui() {
	const struct {
		const char *action;
		const char *chord;
	} binds[] = {
		{"Play/pause (global)", "Shift + Alt + Down"},
		{"Next track (global)", "Shift + Alt + Right"},
		{"Previous track (global)", "Shift + Alt + Left"},
		{"Play/pause", "Space"},
		{"Middle mouse", "Play track"},
		{"Control + Shift + Space", "Jump to playing track"},
		{"Control + Space", "Jump to playing track in current playlist"},
		{"Control + Q", "Play selected tracks"},
		{"Control + Shift + Q", "Append selected tracks to queue"},
	};

	if (ImGui::BeginTable("##hotkeys", 2, ImGuiTableFlags_RowBg)) {
		ImGui::TableSetupColumn("Action");
		ImGui::TableSetupColumn("Combo");

		for (uint32 i = 0; i < ARRAY_LENGTH(binds); ++i) {
			ImGui::TableNextRow();
			ImGui::TableNextColumn();
			ImGui::TextUnformatted(binds[i].action);
			ImGui::TableNextColumn();
			ImGui::TextUnformatted(binds[i].chord);
		}

		ImGui::EndTable();
	}
}

static void show_about_gui() {
	ImGui::SeparatorText("Rat MP");
	ImGui::TextUnformatted("Copyright 2024 Jamie Dennis");
	ImGui::Text("Version: %s", VERSION_STRING);
	ImGui::Text("Build date: %s", __DATE__);
	ImGui::NewLine();
	ImGui::TextUnformatted("This software uses libraries from the FFmpeg project under the LGPLv2.1");
	
	ImGui::NewLine();
	ImGui::SeparatorText("ImGui");
	ImGui::TextUnformatted("Copyright (c) 2014-2024 Omar Cornut");
	
	ImGui::NewLine();
	ImGui::SeparatorText("FreeType");
	ImGui::TextUnformatted("Copyright 1996-2002, 2006 by");
	ImGui::TextUnformatted("David Turner, Robert Wilhelm, and Werner Lemberg");
	
	ImGui::NewLine();
	ImGui::SeparatorText("zlib");
	ImGui::TextUnformatted("Copyright (C) 1995-2023 Jean-loup Gailly and Mark Adler");
	
	ImGui::NewLine();
	ImGui::SeparatorText("bzip2");
	ImGui::TextUnformatted("Copyright (C) 1996-2010 Julian R Seward. All rights reserved.");
	
	ImGui::NewLine();
	ImGui::SeparatorText("libpng");
	ImGui::TextUnformatted("Copyright (c) 1995-2023 The PNG Reference Library Authors.");
	ImGui::TextUnformatted("Copyright (c) 2018-2023 Cosmin Truta.");
	
	ImGui::NewLine();
	ImGui::SeparatorText("xxHash Library");
	ImGui::TextUnformatted("Copyright (c) 2012-2021 Yann Collet");
	ImGui::TextUnformatted("All rights reserved.");
}

static void refresh_layouts() {
	auto add_layout = [](const char *path) {
		Layout layout = {};
		const char *filename = get_file_name(path);
		int filename_length = get_file_name_length_without_extension(path);
		if (filename_length >= sizeof(layout.name)) return true;
		memcpy(layout.name, filename, filename_length);
		log_debug("Add layout: %s\n", layout.name);
		G.layouts.append(layout);
		return true;
	};
	
	G.layouts.reset();
	for_each_file_in_directory(L".\\layouts", add_layout, 1);
}
	
	