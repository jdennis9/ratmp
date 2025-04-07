#ifdef _WIN32
#include <windows.h>

extern "C" HRESULT ole_initialize() {
	return OleInitialize(NULL);
}

#endif