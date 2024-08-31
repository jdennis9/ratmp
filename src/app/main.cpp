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
#include <backends/imgui_impl_opengl3.h>
#include <backends/imgui_impl_win32.h>
#include "stream.h"
#include "ui.h"
#include "util/auto_array_impl.h"
#include "main.h"
#include "embedded.gen.h"
#include "stats.h"
#include <windows.h>
#include <versionhelpers.h>
#include <dwmapi.h>
#include <windowsx.h>
#include <imgui.h>
#include <locale.h>
#include <time.h>
#include <gl/glew.h>
#include <gl/GL.h>
#include <stb_image.h>
#include <ini.h>

#define MIN_FONT_SIZE 8
#define DEFAULT_FONT_SIZE 14
#define DEFAULT_ICON_FONT_SIZE 12
#define MAX_FONT_SIZE 32
#define SINGLE_INSTANCE

IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

static struct {
	int32 resize_width;
	int32 resize_height;
	uint32 width, height;
	HDC hDC;
	HGLRC hRC;
} g_window;

static HWND g_hWnd;
#ifdef SINGLE_INSTANCE
static HANDLE g_foreground_event;
#endif

static struct {
	char font[512];
	char background_path[512];
	HICON icon;
	HMENU tray_popup;
	GLuint thumbnail;
	uint64 time_of_last_input;
	struct {
		GLuint texture;
		GLuint framebuffer;
		int width, height;
	} background;
	bool need_load_thumbnail;
	bool need_load_font;
	int font_size;
	int icon_font_size;
} G;

Config g_config;

#define USER_ASSERT(expr, ...)

static void init_drag_drop(HWND hWnd);

static bool is_first_time_launch() {
	return !file_exists("config.ini");
}

static int load_config_ini_handler(void *dont_care, const char *section, const char *key, const char *value) {
	USE_GLYPH_RANGE_NAMES(range_names);
	
	if (!strcmp(section, "Main")) {
		if (!strcmp(key, "sTheme")) {
			log_debug("Theme: %s\n", value);
			strncpy(g_config.theme, value, sizeof(g_config.theme) - 1);
		}
		else if (!strcmp(key, "iClosePolicy")) {
			g_config.close_policy = (Close_Policy)atoi(value);
		}
		else if (!strcmp(key, "iThumbnailSize")) {
			g_config.thumbnail_size = iclamp(atoi(value), MIN_THUMBNAIL_SIZE, MAX_THUMBNAIL_SIZE);
		}
		else if (!strcmp(key, "iPreviewThumbnailSize")) {
			g_config.preview_thumbnail_size = iclamp(atoi(value), 
													 MIN_PREVIEW_THUMBNAIL_SIZE,
													 MAX_PREVIEW_THUMBNAIL_SIZE);
		}
		else for (uint32 i = 0; i < GLYPH_RANGE__COUNT; ++i) {
			char key_name[64];
			snprintf(key_name, 64, "bLoad%sGlyphs", range_names[i]);
			if (!strcmp(key_name, key)) {
				g_config.include_glyphs[i] = atoi(value);
				break;
			}
		}
	}
	
	return true;
}

void apply_config() {
	load_theme(g_config.theme);
}

void load_config() {
	strcpy(g_config.theme, "default-dark");
	g_config.thumbnail_size = 512;
	g_config.preview_thumbnail_size = 128;
	if (!is_first_time_launch()) {
		ini_parse("config.ini", &load_config_ini_handler, NULL);
	} else {
		save_config();
	}
}

void save_config() {
	log_debug("Saving config\n");
	FILE *file = fopen("config.ini", "w");
	if (!file) return;
	
	USE_GLYPH_RANGE_NAMES(range_names);
	
	fprintf(file, "; Note: Time values are in milliseconds\n");
	fprintf(file, "[Main]\n");
	fprintf(file, "sTheme = %s\n", g_config.theme);
	fprintf(file, "iClosePolicy = %d\n", g_config.close_policy);
	fprintf(file, "iThumbnailSize = %d\n", g_config.thumbnail_size);
	fprintf(file, "iPreviewThumbnailSize = %d\n", g_config.preview_thumbnail_size);
	
	for (int i = 0; i < GLYPH_RANGE__COUNT; ++i) {
		fprintf(file, "bLoad%sGlyphs = %d\n", range_names[i], g_config.include_glyphs[i]);
	}
	
	fclose(file);
}

void set_font(const char *path) {
	G.need_load_font = true;
	strncpy(G.font, path, sizeof(G.font) - 1);
}

const char *get_font() {
	return G.font;
}

void set_font_size(int size) {
	G.need_load_font = true;
	size = MIN(size, MAX_FONT_SIZE);
	size = MAX(size, MIN_FONT_SIZE);
	G.font_size = size;
}

void set_icon_font_size(int size) {
	G.need_load_font = true;
	size = MIN(size, MAX_FONT_SIZE);
	size = MAX(size, MIN_FONT_SIZE);
	G.icon_font_size = size;
}

int get_font_size() {
	return G.font_size;
}

int get_icon_font_size() {
	return G.icon_font_size;
}

static GLuint create_texture(GLenum filter) {
	GLuint texture;
	float border_color[4] = {1.f, 1.f, 1.f, 1.f};
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
	glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border_color);
	return texture;
}

Texture_ID create_texture_from_image(const Image *image) {
	GLuint texture = create_texture(GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, image->width, image->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, image->data);
	return (Texture_ID)texture;
}

static void load_thumbnail() {
	Image image;
	static GLuint texture;
	
	if (stream_get_thumbnail(&image)) {
		if (texture) {
			glDeleteTextures(1, &texture);
			texture = 0;
		}
		
		texture = create_texture(GL_LINEAR);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, g_config.thumbnail_size, g_config.thumbnail_size,
					 0, GL_RGBA, GL_UNSIGNED_BYTE, image.data);
		
		ui_set_thumbnail((void*)texture);
		
		stream_free_thumbnail(&image);
	}
	else {
		ui_set_thumbnail(0);
	}
}

void load_background_image(const char *path) {
	if (!path) {
		glDeleteTextures(1, &G.background.texture);
		glDeleteFramebuffers(1, &G.background.framebuffer);
		G.background.texture = 0;
		G.background.framebuffer = 0;
		memset(G.background_path, 0, sizeof(G.background_path));
		return;
	}
	
	int width, height;
	stbi_uc *image_data = stbi_load(path, &width, &height, NULL, 4);
	if (!image_data) {
		log_debug("Could not load background image \"%s\"\n", path);
		return;
	}
	
	if (!G.background.texture) {
		float border_color[4] = {1.f, 1.f, 1.f, 1.f};
		glGenTextures(1, &G.background.texture);
		glBindTexture(GL_TEXTURE_2D, G.background.texture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border_color);
		
		glGenFramebuffers(1, &G.background.framebuffer);
	}
	
	G.background.width = width;
	G.background.height = height;
	
	glBindTexture(GL_TEXTURE_2D, G.background.texture);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, image_data);
	
	stbi_image_free(image_data);
	
	log_debug("Loaded background \"%s\"\n", path);
	strncpy(G.background_path, path, sizeof(G.background_path)-1);
}

const char *get_background_image_path() {
	if (G.background.texture) return G.background_path;
	else return NULL;
}

static void draw_background() {
	if (!G.background.texture) return;
	
	int width = G.background.width;
	int height = G.background.height;
	int winwidth = g_window.width;
	int winheight = g_window.height;
	float aspect = (float)width/(float)height;
	
	if ((height < winheight) || (height > winheight)) {
		float ratio = (float)winheight / (float)height;
		height *= ratio;
		width *= ratio;
	}
	
	if (width < winwidth) {
		float ratio = (float)winwidth / (float)width;
		width = (int)(width * ratio);
		height = (int)(height * ratio);
	}
	
	glBindFramebuffer(GL_READ_FRAMEBUFFER, G.background.framebuffer);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
	glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, G.background.texture, 0);
	
	glBlitFramebuffer(0, 0, G.background.width, G.background.height, 0, height, width, 0, GL_COLOR_BUFFER_BIT, GL_NEAREST);
}

static bool create_wgl_device(HWND hWnd) {
	HDC hDc = GetDC(hWnd);
	PIXELFORMATDESCRIPTOR pfd = {0};
	pfd.nSize = sizeof(pfd);
	pfd.nVersion = 1;
	pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
	pfd.iPixelType = PFD_TYPE_RGBA;
	pfd.cColorBits = 32;
	
	const int pf = ChoosePixelFormat(hDc, &pfd);
	if (pf == 0)
		return false;
	if (SetPixelFormat(hDc, pf, &pfd) == FALSE)
		return false;
	ReleaseDC(hWnd, hDc);
	
	g_window.hDC = GetDC(hWnd);
	if (!g_window.hRC)
		g_window.hRC = wglCreateContext(hDc);
	return true;
}

static void create_tray_icon(HWND hwnd) {
	NOTIFYICONDATAA data = {};
	
	data.cbSize = sizeof(data);
	data.hWnd = hwnd;
	data.uID = 1;
	data.uFlags = NIF_TIP | NIF_MESSAGE | NIF_ICON;
	data.uCallbackMessage = WM_APP + 1;
	data.hIcon = G.icon;
	data.uVersion = 4;
	
	strcpy(data.szTip, "RAT MP");
	
	Shell_NotifyIconA(NIM_ADD, &data);
}

static void remove_tray_icon(HWND hwnd) {
	NOTIFYICONDATAA data = {};
	
	data.cbSize = sizeof(data);
	data.hWnd = hwnd;
	data.uID = 1;
	
	Shell_NotifyIconA(NIM_DELETE, &data);
}

static void render_frame() {
	ImGui::Render();
	ImDrawData *draw_data = ImGui::GetDrawData();
	glViewport(0, 0, g_window.width, g_window.height);
	glClearColor(0, 0, 0, 0);
	glClear(GL_COLOR_BUFFER_BIT);
	draw_background();
	if (draw_data) {
		ImGui_ImplOpenGL3_RenderDrawData(draw_data);
	}
	SwapBuffers(g_window.hDC);
}

void close_window_to_tray() {
	ShowWindow(g_hWnd, SW_HIDE);
}

// Might use later
#if 0
void begin_main_window_drag() {
	RECT win;
	GetCursorPos(&G.drag.mouse_start);
	GetWindowRect(g_hWnd, &win);
	G.drag.window_start.x = win.left;
	G.drag.window_start.y = win.top;
	G.dragging_window = true;
}

void update_main_window_drag() {
	if (!G.dragging_window) return;
	POINT mouse_delta;
	POINT mouse;
	
	GetCursorPos(&mouse);
	mouse_delta.x = mouse.x - G.drag.mouse_start.x;
	mouse_delta.y = mouse.y - G.drag.mouse_start.y;
	
	SetWindowPos(g_hWnd, NULL, G.drag.window_start.x + mouse_delta.x, G.drag.window_start.y + mouse_delta.y, 0, 0, SWP_NOSIZE);
}

void end_main_window_drag() {
	G.dragging_window = false;
}
#endif

static LRESULT WINAPI window_proc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
		return true;	
	
	switch (msg) {
		case WM_SIZE: {
			g_window.resize_width = LOWORD(lParam);
			g_window.resize_height = HIWORD(lParam);
			g_window.width = g_window.resize_width;
			g_window.height = g_window.resize_height;
			return 0;
		}
		case WM_GETMINMAXINFO: {
			LPMINMAXINFO info = (LPMINMAXINFO)lParam;
			info->ptMinTrackSize.x = 500;
			info->ptMinTrackSize.y = 500;
			break;
		}
		case WM_CLOSE: {
			switch (g_config.close_policy) {
				case CLOSE_POLICY_QUERY: {
					if (MessageBoxA(NULL, "Minimize to tray?", "Close Policy",  MB_YESNO | MB_ICONQUESTION) == IDYES) {
						ShowWindow(hWnd, SW_HIDE);
					}
					else {
						PostQuitMessage(0);
					}
					break;
				}
				case CLOSE_POLICY_EXIT_TO_TRAY: ShowWindow(hWnd, SW_HIDE); break;
				case CLOSE_POLICY_EXIT: PostQuitMessage(0); break;
			}
			return 0;
		}
		case WM_HOTKEY: {
			WPARAM hotkey = wParam;
			ui_handle_hotkey(hotkey);
			return 0;
		}
		case WM_APP + 1: {
			if (LOWORD(lParam) == WM_LBUTTONDOWN) {
				ShowWindow(hWnd, SW_SHOW);
				SetForegroundWindow(hWnd);
			}
			else if (LOWORD(lParam) == WM_RBUTTONDOWN) {
				POINT mouse;
				GetCursorPos(&mouse);
				TrackPopupMenuEx(G.tray_popup, TPM_LEFTBUTTON, mouse.x, mouse.y, hWnd, NULL);
				PostMessage(hWnd, WM_NULL, 0, 0);
			}
			return 0;
		}
		case WM_COMMAND: {
			if (wParam == 1) {
				PostQuitMessage(0);
			}
			return 0;
		}
		case WM_USER+EVENT_STREAM_END_OF_TRACK: {
			ui_next_track();
			return 0;
		}
		case WM_USER+EVENT_STREAM_THUMBNAIL_READY: {
			load_thumbnail();
			return 0;
		}
		case WM_USER+EVENT_STREAM_WAVEFORM_READY: {
			static GLuint texture;
			if (texture) {
				glDeleteTextures(1, &texture);
				texture = 0;
			}
			Image image;
			texture = create_texture(GL_NEAREST);
			stream_get_waveform(&image);
			glBindTexture(GL_TEXTURE_2D, texture);
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, image.width, image.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, image.data);
			ui_set_waveform_image((void*)texture);
			return 0;
		}
		case WM_USER+EVENT_STREAM_TRACK_LOADED: {
			ui_set_waveform_image(NULL);
			return 0;
		}
		case WM_USER+EVENT_STREAM_TRACK_LOAD_FAILED: {
			ui_set_waveform_image(NULL);
			return 0;
		}
		case WM_USER+EVENT_REQUEST_SHOW_WINDOW: {
			ShowWindow(hWnd, SW_SHOW);
			SetForegroundWindow(hWnd);
			return 0;
		}
	}
	
	return DefWindowProcW(hWnd, msg, wParam, lParam);
}

static void enable_vsync() {
	typedef bool wglSwapIntervalEXT_PFN(int);
	wglSwapIntervalEXT_PFN *wglSwapIntervalEXT;
	
	wglSwapIntervalEXT = (wglSwapIntervalEXT_PFN *)wglGetProcAddress("wglSwapIntervalEXT");
	if (!wglSwapIntervalEXT) log_debug("Failed to load WGL_EXT_swap_control GL extension\n");
	else wglSwapIntervalEXT(1);
}

#ifdef SINGLE_INSTANCE
static DWORD foreground_event_thread(LPVOID lParam) {
	while (1) {
		if (WaitForSingleObject(g_foreground_event, INFINITE) == WAIT_OBJECT_0) {
			post_event(EVENT_REQUEST_SHOW_WINDOW, 0, 0);
		}
	}
	
	return 0;
}
#endif //SINGLE_INSTANCE

void post_event(Event_Code event, int64 wparam, int64 lparam) {
	PostMessageW(g_hWnd, WM_USER+event, wparam, lparam);
}

#ifndef NDEBUG
int main(int argc, char *argv[])
#else
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd)
#endif
{
	const wchar_t *WNDCLASS_NAME = L"RAT_WINDOW";
	
#ifdef SINGLE_INSTANCE
	g_foreground_event = CreateEventW(NULL, FALSE, FALSE, L"RAT_INSTANCE");
	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		log_debug("Found existing instance, bringing to foreground\n");
		g_foreground_event = OpenEventW(EVENT_ALL_ACCESS, FALSE, L"RAT_INSTANCE");
		if (g_foreground_event) SetEvent(g_foreground_event);
		else log_error("Failed to open process event");
		return 0;
	}
	CreateThread(NULL, 0, &foreground_event_thread, NULL, 0, NULL);
#endif
	
#ifndef NDEBUG
	HINSTANCE hInstance = GetModuleHandle(NULL);
#endif
	
	(void)OleInitialize(NULL);
	
	stream_open(AUDIO_CLIENT_WASAPI);
	setlocale(LC_ALL, ".65001");
	srand(time(NULL));
	init_stats();
	
	// First time launch, generate default config
	/*if (is_first_time_launch()) {
		strcpy(g_config.theme, "default-dark");
		save_config();
	}*/
	load_config();
	
	G.icon = LoadIconA(hInstance, "WindowIcon");
	
	// Create window
	WNDCLASSEXW wndclass = {};
	wndclass.cbSize = sizeof(wndclass);
	wndclass.style = CS_OWNDC;
	wndclass.lpfnWndProc = &window_proc;
	wndclass.lpszClassName = WNDCLASS_NAME;
	wndclass.hInstance = hInstance;
	wndclass.hIcon = G.icon;
	RegisterClassExW(&wndclass);
	
	g_hWnd = CreateWindowExW(WS_EX_ACCEPTFILES,
							 WNDCLASS_NAME,
							 L"RAT MP " VERSION_STRING,
							 WS_OVERLAPPEDWINDOW,
							 CW_USEDEFAULT,
							 CW_USEDEFAULT,
							 CW_USEDEFAULT,
							 CW_USEDEFAULT,
							 NULL,
							 NULL,
							 wndclass.hInstance,
							 NULL);
	
	// Set dark title bar
	{
		BOOL on = TRUE;
		log_debug("Enabling dark title bar\n");
		DwmSetWindowAttribute(g_hWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &on, sizeof(on));
	}
	
	UpdateWindow(g_hWnd);
	START_TIMER(create_wgl_device, "Create WGL device");
	create_wgl_device(g_hWnd);
	STOP_TIMER(create_wgl_device);
	wglMakeCurrent(g_window.hDC, g_window.hRC);
	START_TIMER(load_opengl, "Load OpenGL library");
	glewInit();
	STOP_TIMER(load_opengl);
	enable_vsync();
	
	SendMessage(g_hWnd, WM_SETICON, ICON_SMALL, (LPARAM)G.icon);
	SendMessage(g_hWnd, WM_SETICON, ICON_BIG, (LPARAM)G.icon);
	
	// Create tray icon  popup context menu
	G.tray_popup = CreatePopupMenu();
	AppendMenuA(G.tray_popup, MF_STRING, 1, "Exit");
	create_tray_icon(g_hWnd);
	
	// Register hotkeys
	RegisterHotKey(g_hWnd, GLOBAL_HOTKEY_PREVIOUS_TRACK, MOD_SHIFT | MOD_ALT, VK_LEFT);
	RegisterHotKey(g_hWnd, GLOBAL_HOTKEY_NEXT_TRACK, MOD_SHIFT | MOD_ALT, VK_RIGHT);
	RegisterHotKey(g_hWnd, GLOBAL_HOTKEY_TOGGLE_PLAYBACK, MOD_SHIFT | MOD_ALT, VK_DOWN);
	
	// Initialize ImGui
	ImGui::CreateContext();
	ImGui::StyleColorsDark();
	ImGui_ImplWin32_InitForOpenGL(g_hWnd);
	ImGui_ImplOpenGL3_Init();
	
	ImGuiIO &io = ImGui::GetIO();
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
	
	// In case font size is not defined in the theme, use a reasonable default
	G.font_size = DEFAULT_FONT_SIZE;
	G.icon_font_size = DEFAULT_ICON_FONT_SIZE;
	
	START_TIMER(init_ui, "Initialize UI");
	init_drag_drop(g_hWnd);
	init_ui();
	STOP_TIMER(init_ui);
	
	//load_config(); // Config needs to be loaded after ImGui and OpenGL are initialized
	apply_config();
	ShowWindow(g_hWnd, SW_NORMAL);
	
	bool running = true;
	while (running) {
		MSG msg;
		uint64 time_since_last_input = time_get_tick() - G.time_of_last_input;
		const uint64 input_idle_threshold = time_get_frequency() / 8; // ~0.125 seconds
		
		check_album_thumbnail_queue();
		
		if (IsWindowVisible(g_hWnd)) {
			if ((time_since_last_input < input_idle_threshold) || 
				(MsgWaitForMultipleObjects(0, NULL, FALSE, 100, QS_ALLINPUT) == WAIT_OBJECT_0)) {
				while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
					TranslateMessage(&msg);
					DispatchMessage(&msg);
					G.time_of_last_input = time_get_tick();
					if (msg.message == WM_QUIT) {
						log_debug("Received WM_QUIT, exiting...\n");
						running = false;
					}
				}
			}
		}
		else {
			GetMessage(&msg, NULL, 0, 0);
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			if (msg.message == WM_QUIT) {
				log_debug("Received WM_QUIT, exiting...\n");
				running = false;
			}
			G.time_of_last_input = time_get_tick();
			continue;
		}
		
		if (!running) break;
		
		//=========================================================================================
		// Replace font if needed
		//=========================================================================================
		//@TODO: Support custom icon fonts
		if (G.need_load_font) {
			G.need_load_font = false;
			
			ImFontConfig cfg = ImFontConfig();
			char path[512];
			snprintf(path, 512, "fonts\\%s", G.font);
			
			static const ImWchar icon_range[] = {
				0xf048, 0xf052, // playback control icons
				0xf026, 0xf028, // volume icons
				0xf074, 0xf074, // shuffle icon
				0
			};
			
			log_debug("Load font %s\n", G.font);
			
			if (file_exists(path)) {
				ImGui_ImplOpenGL3_DestroyFontsTexture();
				
				ImVector<ImWchar> ranges = ImVector<ImWchar>();
				ImFontGlyphRangesBuilder builder = ImFontGlyphRangesBuilder();
				
				builder.AddRanges(io.Fonts->GetGlyphRangesDefault());
				
				if (g_config.include_glyphs[GLYPH_RANGE_JAPANESE]) builder.AddRanges(io.Fonts->GetGlyphRangesJapanese());
				if (g_config.include_glyphs[GLYPH_RANGE_KOREAN]) builder.AddRanges(io.Fonts->GetGlyphRangesKorean());
				if (g_config.include_glyphs[GLYPH_RANGE_CYRILLIC]) builder.AddRanges(io.Fonts->GetGlyphRangesCyrillic());
				if (g_config.include_glyphs[GLYPH_RANGE_GREEK]) builder.AddRanges(io.Fonts->GetGlyphRangesGreek());
				if (g_config.include_glyphs[GLYPH_RANGE_CHINESE]) builder.AddRanges(io.Fonts->GetGlyphRangesChineseSimplifiedCommon());
				if (g_config.include_glyphs[GLYPH_RANGE_THAI]) builder.AddRanges(io.Fonts->GetGlyphRangesThai());
				if (g_config.include_glyphs[GLYPH_RANGE_VIETNAMESE]) builder.AddRanges(io.Fonts->GetGlyphRangesVietnamese());
				
				builder.BuildRanges(&ranges);
				
				io.Fonts->Clear();
				io.Fonts->AddFontFromFileTTF(path, MAX(G.font_size, 8), &cfg, ranges.Data);
				cfg.FontDataOwnedByAtlas = false;
				cfg.MergeMode = true;
				io.Fonts->AddFontFromMemoryTTF(FontAwesome_otf, FontAwesome_otf_len, 
											   G.icon_font_size, &cfg, icon_range);
				ImGui_ImplOpenGL3_CreateFontsTexture();
			}
			else {
				show_message_box(MESSAGE_BOX_WARNING, "Could not find font \"%s\"", G.font);
			}
		}
		
		//=========================================================================================
		// Show UI
		//=========================================================================================
		ImGui_ImplOpenGL3_NewFrame();
		ImGui_ImplWin32_NewFrame();
		ImGui::NewFrame();
		running = show_ui();
		ImGui::EndFrame();
		
		render_frame();
		//glFinish();
	}
	
	stream_close();
	ImGui_ImplOpenGL3_Shutdown();
	ImGui_ImplWin32_Shutdown();
	ImGui::DestroyContext();
	remove_tray_icon(g_hWnd);
	wglDeleteContext(g_window.hRC);
	DestroyWindow(g_hWnd);
	UnregisterClassW(L"main_window", wndclass.hInstance);
#ifdef SINGLE_INSTANCE
	CloseHandle(g_foreground_event);
#endif
	
	return 0;
}

struct Drop_Target : IDropTarget {
	STGMEDIUM medium;
	Track_Drag_Drop_Payload payload;
	
	HRESULT Drop(IDataObject *data, DWORD key_state, POINTL point, DWORD *effect) override {
		FORMATETC format;
		HDROP drop;
		
		format.cfFormat = CF_HDROP;
		format.dwAspect = DVASPECT_CONTENT;
		format.lindex = -1;
		format.ptd = NULL;
		format.tymed = TYMED_HGLOBAL;
		
		if (!SUCCEEDED(data->GetData(&format, &medium))) return E_UNEXPECTED;
		
		drop = (HDROP)medium.hGlobal;
		
		uint32 file_count = DragQueryFile(drop, UINT32_MAX, NULL, 0);
		
		for (uint32 i = 0; i < file_count; ++i) {
			wchar_t path[512];
			DragQueryFileW(drop, i, path, 512);
			payload.paths.append(payload.path_pool.add(path));
		}
		
		ui_accept_drag_drop(&payload);
		
		payload.paths.free();
		payload.path_pool.free();
		
		return 0;
	}
	
	HRESULT DragEnter(IDataObject *data, DWORD key_state, POINTL point, DWORD *effect) override {
		if (*effect & DROPEFFECT_LINK) return S_OK;
		log_error("Unexpected drop effect on DragEnter(): 0x%x\n", *effect);
		return E_UNEXPECTED;
	}
	
	HRESULT DragLeave() override {
		ReleaseStgMedium(&medium);
		return 0;
	}
	
	HRESULT DragOver(DWORD key_state, POINTL point, DWORD *effect) override {
		*effect = DROPEFFECT_LINK;
		return 0;
	}
	
	virtual HRESULT __stdcall QueryInterface(REFIID riid, void **ppvObject) override {
		return E_NOTIMPL;
	}
	
	virtual ULONG __stdcall AddRef(void) override {
		return 0;
	}
	
	virtual ULONG __stdcall Release(void) override {
		return 0;
	}
	
};

static void init_drag_drop(HWND hWnd) {
	static Drop_Target g_drag_drop_target;
	
	HRESULT result = RegisterDragDrop((HWND)hWnd, &g_drag_drop_target);
	
	if (!SUCCEEDED(result)) {
		log_error("RegisterDragDrop failed with code %d (0x%x)\n", result, result);
	}
}
