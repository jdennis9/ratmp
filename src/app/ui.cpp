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

enum Extra_View {
	EXTRA_VIEW_NONE,
	EXTRA_VIEW_THEME,
	EXTRA_VIEW_CONFIG,
	EXTRA_VIEW_HOTKEYS,
	EXTRA_VIEW_SEARCH_RESULTS,
	EXTRA_VIEW_ABOUT,
	EXTRA_VIEW_MISSING_TRACKS,
	EXTRA_VIEW_PLAYBACK_STATS,
};

enum Main_View {
	MAIN_VIEW_TRACKS,
	MAIN_VIEW_ALBUMS,
};

struct Box { ImVec2 pos; ImVec2 size; };

// Layout helper for ImGui windows
class Layout {
	ImVec2 m_base_size;
	ImVec2 m_size;
	ImVec2 m_cursor;

public:
	void init(ImVec2 size) {
		m_base_size = size;
		m_size = size;
	}

	inline Box push_right_pixels(float width) {
		Box box;

		if (width < 0.f) {
			width = fabsf(width);
			width = m_size.x - width;
		}

		box.pos = ImVec2{m_cursor.x, m_cursor.y};
		box.size = ImVec2{width, m_size.y};

		m_cursor.x += width;
		m_size.x -= width;
	}

	inline Box push_right(float width) {
		Box box;
		width *= m_size.x;
		width = ceilf(width);
		box.pos = m_cursor;
		box.size = ImVec2{width, m_size.y};
		m_cursor.x += width;
		m_size.x -= width;

		return box;
	}

	inline Box push_down_pixels(float height) {
		Box box;

		if (height < 0.f) {
			height = fabsf(height);
			height = m_size.y - height;
		}

		box.pos = m_cursor;
		box.size = ImVec2{m_size.x, height};

		m_cursor.y += height;
		m_size.y -= height;

		return box;
	}

	inline Box push_down(float height) {
		return push_down_pixels(height * m_size.y);

	}
};

enum {
	PLAYLIST_LIBRARY,
	PLAYLIST_QUEUE,
	PLAYLIST_USER,
};

static struct {
	Tracklist search_results;
	Stream_State state;
	int32 queue_position;
	Auto_Array<Tracklist> playlists;
	Auto_Array<uint32> playlist_order; // Order of user playlists
	int32 renaming_playlist;
	int32 selected_playlist;
	int32 queued_playlist;
	Main_View main_view;
	Extra_View extra_view;
	ImTextureID thumbnail;
	ImTextureID waveform_image;
	Tracklist drag_drop_payload;
	Track playing_track;
	bool show_extra_view;
	bool shuffle_enabled;
	bool dirty_theme;
} G;

static void show_config_editor_gui();
static void show_hotkey_gui();
static void show_about_gui();
static void queue_tracklist(const Tracklist &tracklist);

static void set_next_window_box(const Box &box) {
	ImGui::SetNextWindowPos(box.pos);
	ImGui::SetNextWindowSize(box.size);
}

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
			
			// Prepare for drag and drop
			if (ImGui::BeginDragDropSource()) {
				Tracklist *payload = new Tracklist();
				
				if (!tracklist.track_is_selected(itrack)) tracklist.select(itrack);
				
				tracklist.copy_selection(payload);
				
				ImGui::SetDragDropPayload("TRACKS", &payload, sizeof(payload));
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
			
			if (ImGui::BeginPopupContextItem()) {
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
			}
		}
		
		// Pop cell color change
		if (playing) ImGui::PopStyleColor();
		
		// ====== Duration
		if (ImGui::TableNextColumn()){
			const char *duration = get_metadata_string(track.metadata, METADATA_DURATION);
			ImGui::TextUnformatted(duration);
		}
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
	
	if (ImGui::BeginTable("##tracklist", 4, table_flags)) {
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

static int32 show_album_list_gui(const Auto_Array<Album>& albums) {
	uint32 album_count = albums.length();
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
			
			if (hovered) ImGui::SetTooltip(name);
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
 
bool show_ui() {
	Layout layout;
	Box window;
	ImGuiIO &io = ImGui::GetIO();
	const ImGuiStyle &style = ImGui::GetStyle();
	const int64 playback_position = stream_get_pos();
	const int64 playback_duration = stream_get_duration();
	bool running = true;
	bool jump_to_playing = false;
	
	G.state = stream_get_state();

	layout.init(io.DisplaySize);
	
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
	if (ImGui::BeginMainMenuBar()) {
		if (ImGui::BeginMenu("File")) {
			bool playlist_available = (G.selected_playlist != -1) && G.playlists.length() && (G.selected_playlist != PLAYLIST_QUEUE);
			
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
		
		if (ImGui::BeginMenu("Edit")) {
			if (ImGui::MenuItem("Edit theme")) {
				G.extra_view = EXTRA_VIEW_THEME;
				G.show_extra_view = true;
			}
			if (ImGui::MenuItem("Preferences")) {
				G.extra_view = EXTRA_VIEW_CONFIG;
				G.show_extra_view = true;
			}
			ImGui::SeparatorText("Playlist");
			if (ImGui::MenuItem("Remove missing tracks")) {
				if (G.selected_playlist >= 0 && G.selected_playlist < (int)G.playlists.m_count) {
					G.playlists[G.selected_playlist].remove_missing_tracks();
					G.playlists[G.selected_playlist].save_to_file();
				}
			}
			ImGui::EndMenu();
		}
		
		if (ImGui::BeginMenu("View")) {
			if (ImGui::MenuItem("Show missing tracks")) {
				G.extra_view = EXTRA_VIEW_MISSING_TRACKS;
				G.show_extra_view = true;
			}
			if (ImGui::MenuItem("Playback statistics")) {
				G.extra_view = EXTRA_VIEW_PLAYBACK_STATS;
				G.show_extra_view = true;
			}
			ImGui::EndMenu();
		}
		
		if (ImGui::BeginMenu("Help")) {
			if (ImGui::MenuItem("Hotkeys")) {
				G.extra_view = EXTRA_VIEW_HOTKEYS;
				G.show_extra_view = true;
			}
			if (ImGui::MenuItem("About")) {
				G.extra_view = EXTRA_VIEW_ABOUT;
				G.show_extra_view = true;
			}
			ImGui::EndMenu();
		}
		
		const float window_button_width = ImGui::GetWindowHeight();
		ImGui::SetCursorPosX(io.DisplaySize.x - (window_button_width*3.f) - 1.f);
		
		// Need to push down the layout to accomodate the menu bar
		layout.push_down_pixels(ImGui::GetWindowHeight());
		ImGui::EndMainMenuBar();
	}

	//=============================================================================================
	// Navigation
	//=============================================================================================
	window = layout.push_right(0.15f);
	set_next_window_box(window);
	if (ImGui::Begin("Playlists", NULL, ImGuiWindowFlags_NoDecoration)) {
		// Image
		if (G.thumbnail) {
			ImVec2 v = ImGui::GetCursorPos();
			v.x = 0;
			ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2{0, 0});
			ImGui::SetCursorPos(v);
			ImGui::Image(G.thumbnail, ImVec2{window.size.x, window.size.x});
			ImGui::PopStyleVar();
		}
		else {
			ImGui::InvisibleButton("##missing_thumbnail", ImVec2{window.size.x, window.size.x});
		}
		
		ImGui::SeparatorText("Navigation");
		
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

		// Playlist list
		if (ImGui::BeginTable("##playlists", 1, ImGuiTableFlags_BordersInner)) {
			ImGui::TableSetupColumn("##names");
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
							ImGui::EndDragDropTarget();
							playlist.save_to_file();
							if (iplaylist == G.queued_playlist) {
								queue_playlist(iplaylist);
							}
						}
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
			}
			ImGui::EndTable();
		}
		
		ImGui::Separator();
		if (ImGui::Selectable("+ New playlist...")) {
			create_playlist();
		}
	}
	ImGui::End();
	
	//=============================================================================================
	// Left side view
	//=============================================================================================
	if (G.show_extra_view) {
		window = layout.push_right(0.4f);
		set_next_window_box(window);
		
		const uint32 flags = ImGuiWindowFlags_NoDecoration ^ ImGuiWindowFlags_NoTitleBar;

		//=============================================================================================
		// Config editor
		//=============================================================================================
		if (G.extra_view == EXTRA_VIEW_CONFIG) {
			if (ImGui::Begin("Edit Preferences", &G.show_extra_view, flags)) {
				show_config_editor_gui();
			}
			ImGui::End();
		}
		
		//=============================================================================================
		// Theme editor
		//=============================================================================================
		else if (G.extra_view == EXTRA_VIEW_THEME) {
			ImGuiWindowFlags unsaved = G.dirty_theme ? ImGuiWindowFlags_UnsavedDocument : 0;
			if (ImGui::Begin("Edit Theme", &G.show_extra_view, flags|unsaved)) {
				G.dirty_theme = show_theme_editor_gui();
			}
			ImGui::End();
		}
		
		//=============================================================================================
		// Hotkeys
		//=============================================================================================
		else if (G.extra_view == EXTRA_VIEW_HOTKEYS) {
			if (ImGui::Begin("Hotkeys", &G.show_extra_view, flags)) {
				show_hotkey_gui();
			}
			ImGui::End();
		}
		
		//=============================================================================================
		// Search results
		//=============================================================================================
		else if (G.extra_view == EXTRA_VIEW_SEARCH_RESULTS) {
			if (ImGui::Begin("Search Results", &G.show_extra_view, flags)) {
				show_track_list_gui(G.search_results, -1, NULL);
			}
			ImGui::End();
		}
		
		//=============================================================================================
		// About
		//=============================================================================================
		else if (G.extra_view == EXTRA_VIEW_ABOUT) {
			if (ImGui::Begin("About", &G.show_extra_view, flags)) {
				show_about_gui();
			}
			ImGui::End();
		}
		
		//=============================================================================================
		// Missing tracks
		//=============================================================================================
		else if (G.extra_view == EXTRA_VIEW_MISSING_TRACKS) {
			if (ImGui::Begin("Missing Tracks", &G.show_extra_view, flags)) {
				if ((G.selected_playlist >= 0) && (G.selected_playlist < (int)G.playlists.m_count)) {
					Tracklist& playlist = G.playlists[G.selected_playlist];
					for (uint32 i = 0; i < playlist.m_missing_tracks.m_count; ++i) {
						char path[512];
						retrieve_file_path(playlist.m_missing_tracks[i], path, sizeof(path));
						ImGui::TextUnformatted(path);
					}
				}
			}
			ImGui::End();
		}
		//=============================================================================================
		// Playback stats
		//=============================================================================================
		else if (G.extra_view == EXTRA_VIEW_PLAYBACK_STATS) {
			if (ImGui::Begin("Playback Statistics", &G.show_extra_view, flags)) {
				show_playback_stats_gui();
			}
			ImGui::End();
		}
	}
	
	//=============================================================================================
	// Track list
	//=============================================================================================
	window = layout.push_down_pixels(-66);
	set_next_window_box(window);
	if (G.main_view == MAIN_VIEW_ALBUMS) {
		const Auto_Array<Album>& albums = get_albums();
		if (ImGui::Begin("Albums", NULL, ImGuiWindowFlags_NoDecoration)) {
			show_album_list_gui(albums);
		}
		ImGui::End();
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
		
		if (ImGui::Begin(window_title, NULL, ImGuiWindowFlags_NoDecoration ^ ImGuiWindowFlags_NoTitleBar)) {
			if (ImGui::InputTextWithHint("##filter", "Filter", filter_text, sizeof(filter_text), ImGuiInputTextFlags_EnterReturnsTrue)) {
				G.search_results.clear();
				if (filter.enabled && filter.filter[0]) {
					playlist.copy_with_filter(&G.search_results, &filter);
					G.extra_view = EXTRA_VIEW_SEARCH_RESULTS;
					G.show_extra_view = true;
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
		
		ImGui::End();
	}
	else {
		if (ImGui::Begin("##empty_tracklist", NULL, ImGuiWindowFlags_NoDecoration)) {
		}
		ImGui::End();
	}
	
	//=============================================================================================
	// Control panel
	//=============================================================================================
	window = layout.push_right(1);
	set_next_window_box(window);
	if (ImGui::Begin("Control Panel", NULL, ImGuiWindowFlags_NoDecoration)) {
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
				cursor.x = (window.size.x / 2) - (text_size.x / 2) - style.ItemInnerSpacing.x;
				ImGui::SetCursorPos(cursor);
				ImGui::TextUnformatted(pt);
			}

			// Volume button
			ImGui::SameLine();
			if (0) {
				const char *icon = u8"\xf028";
				ImVec2 text_size = ImGui::CalcTextSize(icon);
				ImVec2 cursor = ImGui::GetCursorPos();
				cursor.x = window.size.x - text_size.x - style.ItemInnerSpacing.x - style.WindowPadding.x;
				ImGui::SetCursorPos(cursor);
				if (small_selectable(icon)) {
					ImGui::OpenPopup("##volume_slider");
				}

				if (ImGui::BeginPopup("##volume_slider")) {
					float volume = stream_get_volume();
					if (vertical_volume_slider("##slider", ImVec2{14, 60}, &volume, 0.f, 1.f)) 
						stream_set_volume(volume);
					ImGui::EndPopup();
				}
			}
			else {
				const char *icon = u8"\xf028";
				ImVec2 icon_size = ImGui::CalcTextSize(icon);
				float volume = stream_get_volume();
				ImVec2 cursor = ImGui::GetCursorPos();
				float width = 90.f;
				cursor.x = window.size.x - width - (style.ItemInnerSpacing.x*2.f) - (style.WindowPadding.x*2.f) - icon_size.x;
				ImGui::SetCursorPos(cursor);
				if (circle_handle_slider(icon, &volume, 0.f, 1.f, width)) {
					stream_set_volume(volume);
					ImGui::SetTooltip("%d%%", (int)(100.f * volume));
				}
			}
			
			// Seek bar
			if (seek_slider("##seek", playback_position, playback_duration, &new_pos, WAVEFORM_IMAGE_HEIGHT, G.waveform_image)) {
				stream_seek(new_pos*1000);
			}
		}
	}
	ImGui::End();

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
	if (ImGui::InputInt("Preview thumbnail size", &config.preview_thumbnail_size)) {
		config.thumbnail_size = iclamp(config.thumbnail_size, 
									   MIN_PREVIEW_THUMBNAIL_SIZE, MAX_PREVIEW_THUMBNAIL_SIZE);
		need_save = true;
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
