#include <windows.h>
#include <windowsx.h>
#include <dwrite.h>
#include <stdint.h>
#include "common.h"

extern "C" HRESULT ole_initialize() {
	return OleInitialize(NULL);
}

extern "C" bool get_font_file_from_logfont(const LOGFONTW *logfont, char *buf, int32_t buf_size) {
	IDWriteFactory *factory;
	IDWriteGdiInterop *interop;
	IDWriteFont *font;
	IDWriteFontFace *face;
	IDWriteFontFile *file;
	IDWriteFontFileLoader *loader;
	IDWriteLocalFontFileLoader *local_loader;
	LPCVOID font_file_ref;
	UINT font_file_ref_size;
	// Only want the first file
	UINT file_count = 1;
	HRESULT hr;
	HFONT hfont;
	HDC hdc;
	WCHAR file_path[512];

	hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED,  __uuidof(IDWriteFactory), (IUnknown**)&factory);
	if (!SUCCEEDED(hr)) 
		return false;
	defer(factory->Release());

	hr = factory->GetGdiInterop(&interop);
	if (!SUCCEEDED(hr)) 
		return false;
	defer(interop->Release());

#if 1
	hr = interop->CreateFontFromLOGFONT(logfont, &font);
	if (!SUCCEEDED(hr)) 
		return false;
	defer(font->Release());

	hr = font->CreateFontFace(&face);
	if (!SUCCEEDED(hr)) 
		return false;
	defer(face->Release());
#else
	hfont = CreateFontIndirectW(logfont);
	hdc = CreateCompatibleDC(NULL);
	SelectFont(hdc, hfont);
	if (hfont == NULL)
		return false;

	hr = interop->CreateFontFaceFromHdc(hdc, &face);
	if (!SUCCEEDED(hr)) 
		return false;
#endif

	hr = face->GetFiles(&file_count, &file);
	if (!SUCCEEDED(hr)) 
		return false;
	defer(file->Release());

	file->GetReferenceKey(&font_file_ref, &font_file_ref_size);

	hr = file->GetLoader(&loader);
	if (!SUCCEEDED(hr))
		return false;
	defer(loader->Release());
	hr = loader->QueryInterface(__uuidof(IDWriteLocalFontFileLoader), (void **)&local_loader);
	if (!SUCCEEDED(hr))
		return false;
	defer(local_loader->Release());

	local_loader->GetFilePathFromKey(font_file_ref, font_file_ref_size, file_path, 512);
	
	WideCharToMultiByte(CP_UTF8, 0, file_path, wcslen(file_path), buf, buf_size, NULL, NULL);

	return true;
}
