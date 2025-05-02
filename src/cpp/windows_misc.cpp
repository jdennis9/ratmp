#ifdef _WIN32
#include <windows.h>

extern "C" HRESULT ole_initialize() {
	return OleInitialize(NULL);
}

extern "C" bool is_system_light_theme() {
	char buffer[4];
	DWORD buffer_size = 4;

	LSTATUS hr = RegGetValueW(
		HKEY_CURRENT_USER,
		L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
		L"AppsUseLightTheme",
		RRF_RT_REG_DWORD,
		NULL,
		buffer,
		&buffer_size
	);

	if (hr != ERROR_SUCCESS) {
		return false;
	}

	UINT32 val = ((UINT32)buffer[3] << 24) |
		((UINT32)buffer[2] << 16)  |
		((UINT32)buffer[1] << 8) |
		((UINT32)buffer[0]);

	return val == 1;
}

#endif