package wasapi;

/*foreign import lib {
	"mm",
};*/

import win "core:sys/windows";
import "core:c";

IUnknown :: win.IUnknown;
IUnknown_VTable :: win.IUnknown_VTable;
REFERENCE_TIME :: win.LONGLONG;
IID :: win.IID;

EDataFlow :: enum c.int {
	eRender,
	eCapture,
	eAll,
};

AUDCLNT_SHAREMODE :: enum c.int {
	SHARED,
	EXCLUSIVE,
};

WAVEFORMATEX :: struct {
	wFormatTag: win.WORD,
	nChannels: win.WORD,
	nSamplesPerSec: win.WORD,
	nAvgBytesPerSec: win.WORD,
	nBlockAlign: win.WORD,
	wBitsPerSample: win.WORD,
	cbSize: win.WORD,
};

IMMDevice_UUID_STRING :: "D666063F-1587-4E43-81F1-B948E807363F";
IMMDevice_UUID := &IID{0xD666063F, 0x1587, 0x4E43, {0x81, 0xF1, 0xB9, 0x48, 0xE8, 0x07, 0x36, 0x3F}};
IMMDevice_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	Activate: proc "system" (iid: win.REFIID, dwClsCtx: win.DWORD, pActivationParams: ^win.PROPVARIANT, ppInterface: ^rawptr) -> win.HRESULT,
	OpenPropertyStore: proc "system" (stgmAccess: win.DWORD, ppProperties: ^win.IPropertyStore) -> win.HRESULT,
	GetId: proc "system" (ppstrId: ^win.LPWSTR) -> win.HRESULT,
	GetState: proc "system" (pdwState: ^win.DWORD) -> win.HRESULT,
};

IMMDevice :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: IMMDevice_VTable,
};

IMMDeviceCollection_UUID_STRING :: "0BD7A1BE-7A1A-44DB-8397-CC5392387B5E";
IMMDeviceCollection_UUID := &IID{0x0BD7A1BE, 0x7A1A, 0x44DB, {0x83, 0x97, 0xCC, 0x53, 0x92, 0x38, 0x7B, 0x5E}};
IMMDeviceCollection_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	GetCount: proc "system" (pcDevices: ^win.UINT) -> win.HRESULT,
	Item: proc "system" (nDevice: win.UINT, pDevice: ^IMMDevice) -> win.HRESULT,
};

IMMDeviceCollection :: struct #raw_union {
	#subtype iunknown: IUnknown_VTable,
	using vtable: ^IMMDeviceCollection,
};

IMMDeviceEnumerator_UUID_STRING :: "A95664D2-9614-4F35-A746-DE8DB63617E6";
IMMDeviceEnumerator_UUID := &IID{0xA95664D2, 0x9614, 0x4F35, {0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6}};
IMMDeviceEnumerator_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	EnumAudioEndpoints: proc "system" (datafloat: EDataFlow, dwStateMask: win.DWORD, ppDevices: ^IMMDeviceCollection) -> win.HRESULT,
};

IMMDeviceEnumerator :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^IMMDeviceEnumerator_VTable,
};

IAudioClient_UUID_STRING :: "1CB9AD4C-DBFA-4c32-B178-C2F568A703B2";
IAudioClient_UUID := &IID{0x1CB9AD4C, 0xDBFA, 0x4c32, {0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2}};
IAudioClient_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	Initialize: proc "system" (
		ShareMode: AUDCLNT_SHAREMODE,
		StreamFlags: win.DWORD,
		hnsBufferDuration: REFERENCE_TIME,
		hnsPeriodicity: REFERENCE_TIME,
		pFormat: ^WAVEFORMATEX,
		AudioSessionGuid: win.LPGUID
	) -> win.HRESULT,

	GetBufferSize: proc "system" (pNumBufferFrames: ^u32) -> win.HRESULT,
	GetStreamLatency: proc "system" (phnsLatency: ^REFERENCE_TIME) -> win.HRESULT,
	GetCurrentPadding: proc "system" (pNumPaddingFrames: ^u32) -> win.HRESULT,
	IsFormatSupported: proc "system" (ShareMode: AUDCLNT_SHAREMODE, pFormat: ^WAVEFORMATEX, ppClosestMatch: ^WAVEFORMATEX) -> win.HRESULT,
	GetMixFormat: proc "system" (ppDeviceFormat: ^^WAVEFORMATEX) -> win.HRESULT,
	GetDevicePeriod: proc "system" (phnsDefaultDevicePeriod: ^REFERENCE_TIME, phnsMinimumDevicePeriod: ^REFERENCE_TIME) -> win.HRESULT,
	Start: proc "system" () -> win.HRESULT,
	Stop: proc "system" () -> win.HRESULT,
	Reset: proc "system" () -> win.HRESULT,
	SetEventHandle: proc "system" (eventHandle: win.HANDLE) -> win.HRESULT,
	GetService: proc "system" (riid: win.REFIID, ppv: ^rawptr) -> win.HRESULT,
};

IAudioClient :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: IAudioClient_VTable,
};

IAudioRenderClient_UUID_STRING :: "F294ACFC-3146-4483-A7BF-ADDCA7C260E2";
IAudioRenderClient_UUID := &IID{0xF294ACFC, 0x3146, 0x4483, {0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2}};
IAudioRenderClient_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	GetBuffer: proc "system" (NumFramesRequested: u32, ppData: ^u8) -> win.HRESULT,
	ReleaseBuffer: proc "system" (NumFramesWritten: u32, dwFlags: win.DWORD) -> win.HRESULT,
};

IAudioRenderClient :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: IAudioRenderClient_VTable,
};

ISimpleAudioVolume_UUID_STRING :: "87CE5498-68D6-44E5-9215-6DA47EF883D8";
ISimpleAudioVolume_UUID := &IID{0x87CE5498, 0x68D6, 0x44E5, {0x92, 0x15, 0x6D, 0xA4, 0x7E, 0xF8, 0x83, 0xD8}};
ISimpleAudioVolume_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	SetMasterVolume: proc "system" (fLevel: f32) -> win.HRESULT,
	GetMasterVolume: proc "system" (pfLevel: ^f32) -> win.HRESULT,
	SetMute: proc "system" (bMute: win.BOOL) -> win.HRESULT,
	GetMute: proc "system" (pbMute: ^win.BOOL) -> win.HRESULT,
};

ISimpleAudioVolume :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ISimpleAudioVolume_VTable,
};
