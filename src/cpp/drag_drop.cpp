#ifdef _WIN32
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

typedef uint32_t u32;
#define PATH_LENGTH 384

enum {
	SIGNAL_,
};

struct Interface {
	void (*add_file)(const char *path);
	void (*begin)();
	void (*mouse_over)(float x, float y);
	void (*cancel)();
	void (*drop)();
};

static Interface iface;
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

        u32 file_count = DragQueryFile(drop, UINT32_MAX, NULL, 0);
        u32 tracks_added_count = 0;

        for (u32 i = 0; i < file_count; ++i) {
            wchar_t path[PATH_LENGTH] = {};
            char path_u8[PATH_LENGTH] = {};
            DragQueryFileW(drop, i, path, PATH_LENGTH);
			WideCharToMultiByte(CP_UTF8, 0, path, wcslen(path), path_u8, PATH_LENGTH, NULL, NULL);
            iface.add_file(path_u8);
        }


        // Tell ImGui we released left mouse because Windows eats the event when dropping
        // files into the window
        //ImGui::GetIO().AddMouseButtonEvent(ImGuiMouseButton_Left, false);

        //tell_main_weve_dropped_the_drag_drop_payload();
		iface.drop();

        return 0;
    }

    HRESULT DragEnter(IDataObject *data, DWORD key_state, POINTL point, DWORD *effect) override {
        iface.begin();
        *effect |= DROPEFFECT_COPY;
        return S_OK;
    }

    HRESULT DragLeave() override {
        ReleaseStgMedium(&medium);
        //clear_file_drag_drop_payload();
		iface.cancel();
        return S_OK;
    }

    HRESULT DragOver(DWORD key_state, POINTL point_l, DWORD *effect) override {
        POINT point;
        point.x = point_l.x;
        point.y = point_l.y;
		ScreenToClient(window, &point);
		iface.mouse_over((float)point.x, (float)point.y);
        *effect |= DROPEFFECT_COPY;
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

extern "C" void drag_drop_init_for_windows(HWND hWnd) {
    static Drop_Target g_drag_drop_target;
    HRESULT hr;

    printf("Registering drag drop interface\n");

    hr = RegisterDragDrop((HWND)hWnd, &g_drag_drop_target);
    if (!SUCCEEDED(hr)) {
        printf("****** Failed to register drag drop: 0x%x\n", hr);
    }
    window = hWnd;
}

extern "C" void drag_drop_set_interface(Interface *iface_) {
	iface = *iface_;
}

#endif
