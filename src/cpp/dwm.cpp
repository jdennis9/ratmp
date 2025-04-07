#ifdef _WIN32
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>

extern "C" void dwm_set_dark_title_bar(void *hwnd, bool on) {
	BOOL on_ = on;
	DwmSetWindowAttribute((HWND)hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &on_, sizeof(on_));
}
#endif
