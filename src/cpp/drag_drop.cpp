#ifdef _WIN32
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

typedef uint32_t u32;
#define PATH_LENGTH 384

static void (*drop_callback)(const char *path);
static HWND window;

struct Drop_Target : IDropTarget {
    STGMEDIUM medium;

    HRESULT Drop(IDataObject *data, DWORD key_state, POINTL point, DWORD *effect) override {
        FORMATETC format;
        HDROP drop;

        *effect |= DROPEFFECT_COPY;

        format.cfFormat = CF_HDROP;
        format.dwAspect = DVASPECT_CONTENT;
        format.lindex = -1;
        format.ptd = NULL;
        format.tymed = TYMED_HGLOBAL;
        medium.tymed = TYMED_HGLOBAL;

        if (!SUCCEEDED(data->GetData(&format, &medium))) return E_UNEXPECTED;

        drop = (HDROP)medium.hGlobal;

        u32 file_count = DragQueryFileW(drop, UINT32_MAX, NULL, 0);
        u32 tracks_added_count = 0;

        for (u32 i = 0; i < file_count; ++i) {
            wchar_t path[PATH_LENGTH] = {};
            char path_u8[PATH_LENGTH] = {};
            DragQueryFileW(drop, i, path, PATH_LENGTH);
			WideCharToMultiByte(CP_UTF8, 0, path, wcslen(path), path_u8, PATH_LENGTH, NULL, NULL);
            drop_callback(path_u8);
        }

        drop_callback(NULL);

        return 0;
    }

    HRESULT DragEnter(IDataObject *data, DWORD key_state, POINTL point, DWORD *effect) override {
        return S_OK;
    }

    HRESULT DragLeave() override {
        return S_OK;
    }

    HRESULT DragOver(DWORD key_state, POINTL point_l, DWORD *effect) override {
        return S_OK;
    }

    virtual HRESULT __stdcall QueryInterface(REFIID riid, void **ppvObject) override {
        return S_OK;
    }

    virtual ULONG __stdcall AddRef(void) override {
        return 0;
    }

    virtual ULONG __stdcall Release(void) override {
        return 0;
    }

};

extern "C" void drag_drop_init(HWND hWnd, void (*callback)(const char *files)) {
    static Drop_Target g_drag_drop_target;
    HRESULT hr;

    drop_callback = callback;

    RegisterDragDrop((HWND)hWnd, &g_drag_drop_target);
    window = hWnd;
}

#endif
