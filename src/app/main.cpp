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
#include <backends/imgui_impl_dx10.h>
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
#include <stb_image.h>
#include <ini.h>
#include <d3d10.h>

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
	Texture *thumbnail;
	uint64 time_of_last_input;
	struct {
		Texture *texture;
		int width, height;
	} background;
	bool need_load_thumbnail;
	bool need_load_font;
	int font_size;
	int icon_font_size;
	float dpi_scale;
} G;

static struct {
	ID3D10Device *device;
	IDXGISwapChain *swapchain;
	ID3D10RenderTargetView *render_target;
} dx;

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
		else if (!strcmp(key, "iWaveformHorizRes")) {
			// 512 to 4096
			g_config.waveform_height_power = iclamp(atoi(value), MIN_WAVEFORM_HEIGHT_POWER, MAX_WAVEFORM_HEIGHT_POWER);
		}
		else if (!strcmp(key, "iWaveformVerticalRes")) {
			// 16 to 512
			g_config.waveform_width_power = iclamp(atoi(value), MIN_WAVEFORM_WIDTH_POWER, MAX_WAVEFORM_WIDTH_POWER);
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
	g_config.waveform_height_power = 10; // 1024
	g_config.waveform_width_power = 7; // 128
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
	fprintf(file, "sTheme = \"%s\"\n", g_config.theme);
	fprintf(file, "iClosePolicy = %d\n", g_config.close_policy);
	fprintf(file, "iThumbnailSize = %d\n", g_config.thumbnail_size);
	fprintf(file, "iPreviewThumbnailSize = %d\n", g_config.preview_thumbnail_size);
	fprintf(file, "iWaveformVerticalRes = %d\n", g_config.waveform_width_power);
	fprintf(file, "iWaveformHorizRes = %d\n", g_config.waveform_height_power);
	
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

Texture *create_texture(uint32 width, uint32 height, void *data) {
	ID3D10Texture2D *texture;
	ID3D10ShaderResourceView *view;

	D3D10_TEXTURE2D_DESC desc = {};
	desc.Width = width;
	desc.Height = height;
	desc.MipLevels = 1;
	desc.ArraySize = 1;
	desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	desc.SampleDesc.Count = 1;
	desc.Usage = D3D10_USAGE_DYNAMIC;
	desc.BindFlags = D3D10_BIND_SHADER_RESOURCE;
	desc.CPUAccessFlags = D3D10_CPU_ACCESS_WRITE;

	dx.device->CreateTexture2D(&desc, NULL, &texture);

	D3D10_SHADER_RESOURCE_VIEW_DESC sr = {};
	sr.Format = desc.Format;
	sr.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
	sr.Texture2D.MipLevels = 1;
	dx.device->CreateShaderResourceView(texture, &sr, &view);

	D3D10_MAPPED_TEXTURE2D mapped;
	texture->Map(D3D10CalcSubresource(0, 0, 1), D3D10_MAP_WRITE_DISCARD, 0, &mapped);
	
	uint8 *out = (uint8*)mapped.pData;
	uint8 *in = (uint8*)data;

	for (uint32 row = 0; row < height; ++row) {
		uint32 row_offset = row * mapped.RowPitch;
		for (uint32 col = 0; col < width; ++col) {
			uint32 col_offset = col * 4;
			out[row_offset+col_offset+0] = in[0];
			out[row_offset+col_offset+1] = in[1];
			out[row_offset+col_offset+2] = in[2];
			out[row_offset+col_offset+3] = in[3];

			in += 4;
		}
	}
	
	texture->Unmap(D3D10CalcSubresource(0, 0, 1));
	texture->Release();

	return view;
}

Texture *create_texture_from_image(const Image *image) {
	return create_texture(image->width, image->height, image->data);
}

void destroy_texture(Texture *texture) {
	texture->Release();
}

static void load_thumbnail() {
	Image image;
	static Texture *texture;
	
	if (stream_get_thumbnail(&image)) {
		if (texture) {
			destroy_texture(texture);
			texture = NULL;
		}

		texture = create_texture_from_image(&image);
		ui_set_thumbnail(texture);
		stream_free_thumbnail(&image);
	}
	else {
		ui_set_thumbnail(NULL);
	}
}

void load_background_image(const char *path) {
	if (!path) {
		if (G.background.texture) destroy_texture(G.background.texture);
		G.background.texture = NULL;
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
		Image image = {};
		image.width = width;
		image.height = height;
		image.data = image_data;

		G.background.texture = create_texture_from_image(&image);
	}

	G.background.width = width;
	G.background.height = height;

	stbi_image_free(image_data);
	strncpy_s(G.background_path, path, sizeof(G.background_path)-1);
}

const char *get_background_image_path() {
	if (G.background.texture) return G.background_path;
	else return NULL;
}

static void draw_background() {
	if (!G.background.texture) return;
	ImDrawList *drawlist = ImGui::GetBackgroundDrawList(ImGui::GetMainViewport());
	
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

	ImVec2 min = ImVec2(0, 0);
	ImVec2 max = ImVec2((float)width, (float)height);

	drawlist->AddImage(G.background.texture, min, max, ImVec2(0, 0), ImVec2(1, 1));
}

static void create_render_target() {
	ID3D10Texture2D *texture;
	dx.swapchain->GetBuffer(0, IID_PPV_ARGS(&texture));
	dx.device->CreateRenderTargetView(texture, NULL, &dx.render_target);
	texture->Release();
}

static void destroy_render_target() {
	if (dx.render_target) {
		dx.render_target->Release();
		dx.render_target = NULL;
	}
}

static bool create_d3d_device(HWND hWnd) {
	DXGI_SWAP_CHAIN_DESC swapchain = {};
	swapchain.BufferCount = 2;
	swapchain.BufferDesc.Width = 0;
	swapchain.BufferDesc.Height = 0;
	swapchain.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	swapchain.BufferDesc.RefreshRate.Numerator = 60;
	swapchain.BufferDesc.RefreshRate.Denominator = 1;
	swapchain.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
	swapchain.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	swapchain.OutputWindow = hWnd;
	swapchain.SampleDesc.Count = 1;
	swapchain.SampleDesc.Quality = 0;
	swapchain.Windowed = TRUE;
	swapchain.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

	int flags = 0;
#ifndef NDEBUG
	flags |= D3D10_CREATE_DEVICE_DEBUG;
#endif

	HRESULT result = D3D10CreateDeviceAndSwapChain(NULL, D3D10_DRIVER_TYPE_HARDWARE, NULL,
			flags, D3D10_SDK_VERSION,
			&swapchain, &dx.swapchain, &dx.device);

	if (result == DXGI_ERROR_UNSUPPORTED) {
		result = D3D10CreateDeviceAndSwapChain(NULL, D3D10_DRIVER_TYPE_HARDWARE, NULL,
				flags, D3D10_SDK_VERSION,
				&swapchain, &dx.swapchain, &dx.device);
	}

	if (result != S_OK) {
		show_message_box(MESSAGE_BOX_ERROR, "Device does not support DirectX10");
		return false;
	}

	create_render_target();

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
	
	strcpy_s(data.szTip, "RAT_MP");
	
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
	draw_background();
	ImGui::Render();

	const float clear_color[4] = {0.f, 0.f, 0.f, 1.f};
	dx.device->OMSetRenderTargets(1, &dx.render_target, NULL);
	dx.device->ClearRenderTargetView(dx.render_target, clear_color);

	ImDrawData *draw_data = ImGui::GetDrawData();
	if (draw_data) {
		ImGui_ImplDX10_RenderDrawData(draw_data);
	}
	dx.swapchain->Present(1, 0);
}

void close_window_to_tray() {
	ShowWindow(g_hWnd, SW_HIDE);
}

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
				case CLOSE_POLICY__COUNT: break;
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
		case WM_DPICHANGED: {
			G.dpi_scale = ImGui_ImplWin32_GetDpiScaleForHwnd(g_hWnd);
			G.need_load_font = true;
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
			static Texture *texture;
			if (texture) destroy_texture(texture);
			Image image;
			stream_get_waveform(&image);
			texture = create_texture_from_image(&image);
			ui_set_waveform_image(texture);
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
	// This needs to go before any window creation
	ImGui_ImplWin32_EnableDpiAwareness();
	
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
	
	G.dpi_scale = ImGui_ImplWin32_GetDpiScaleForHwnd(g_hWnd);
	
	// Set dark title bar
	{
		BOOL on = TRUE;
		log_debug("Enabling dark title bar\n");
		DwmSetWindowAttribute(g_hWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &on, sizeof(on));
	}
	
	UpdateWindow(g_hWnd);
	START_TIMER(create_d3d10_device, "Create DirectX10 device");
	create_d3d_device(g_hWnd);
	STOP_TIMER(create_d3d10_device);
	
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
	ImGui_ImplWin32_Init(g_hWnd);
	ImGui_ImplDX10_Init(dx.device);
	
	ImGuiIO &io = ImGui::GetIO();
	io.ConfigFlags |=
		ImGuiConfigFlags_NavEnableKeyboard|ImGuiConfigFlags_DockingEnable;
	
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

		if (g_window.resize_width != 0) {
			destroy_render_target();
			dx.swapchain->ResizeBuffers(1, g_window.resize_width, g_window.resize_height, DXGI_FORMAT_UNKNOWN, 0);
			g_window.resize_width = g_window.resize_height = 0;
			create_render_target();
		}

		//=========================================================================================
		// Replace font if needed
		//=========================================================================================
		//@TODO: Support custom icon fonts
		if (G.need_load_font) {
			G.need_load_font = false;
			
			ImFontConfig cfg = ImFontConfig();
			cfg.RasterizerDensity = G.dpi_scale;
			
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
				ImGui_ImplDX10_InvalidateDeviceObjects();
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
				io.Fonts->AddFontFromFileTTF(path, 
											 MAX((int)(G.font_size*G.dpi_scale), 8), 
											 &cfg, ranges.Data);
				cfg.FontDataOwnedByAtlas = false;
				cfg.MergeMode = true;
				io.Fonts->AddFontFromMemoryTTF(FontAwesome_otf, FontAwesome_otf_len, 
											   (int)(G.icon_font_size*G.dpi_scale), &cfg, icon_range);
				ImGui_ImplDX10_CreateDeviceObjects();
			}
			else {
				show_message_box(MESSAGE_BOX_WARNING, "Could not find font \"%s\"", G.font);
			}
		}
		
		//=========================================================================================
		// Show UI
		//=========================================================================================
		ImGui_ImplDX10_NewFrame();
		ImGui_ImplWin32_NewFrame();
		ImGui::NewFrame();
		running = show_ui();
		ImGui::EndFrame();
		
		render_frame();
		//glFinish();
	}
	
	stream_close();
	ImGui_ImplDX10_Shutdown();
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
		log_error("Unexpected drop effect on DragEnter(): 0x%x\n", (uint32)*effect);
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
		log_error("RegisterDragDrop failed with code %d (0x%x)\n", (uint32)result, (uint32)result);
	}
}

const char *lazy_format(const char *fmt, ...) {
	thread_local char buffer[4096];
	va_list va;
	va_start(va, fmt);
	vsnprintf(buffer, sizeof(buffer), fmt, va);
	va_end(va);
	return buffer;
}

