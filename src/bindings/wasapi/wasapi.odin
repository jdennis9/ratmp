package wasapi

import win "core:sys/windows"
import "core:c"

IUnknown :: win.IUnknown
IUnknown_VTable :: win.IUnknown_VTable
REFERENCE_TIME :: win.LONGLONG
IID :: win.IID


PKEY_DeviceInterface_FriendlyName := &win.PROPERTYKEY{{0x026e516e, 0xb814, 0x414b, {0x83, 0xcd, 0x85, 0x6d, 0x6f, 0xef, 0x48, 0x22}}, 2}

CLSID_MMDeviceEnumerator := win.GUID{0xBCDE0395, 0xE52F, 0x467C, {0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E}}

EDataFlow :: enum c.int {
	eRender,
	eCapture,
	eAll,
}

ERole :: enum c.int {
	eConsole,
	eMultiMedia,
	eCommunications,
}

VARTYPE :: enum c.ushort {
	NONE,
}

PROPVARIANT :: struct {
	vt: VARTYPE,
	wReserved1: win.WORD,
	wReserved2: win.WORD,
	wReserved3: win.WORD,
	val: struct #raw_union {
		lpwszVal: win.LPCWSTR,
		dummy: [512-8]u8,
	},
}

AUDCLNT_SHAREMODE :: enum c.int {
	SHARED,
	EXCLUSIVE,
}

WAVEFORMATEX :: struct {
	wFormatTag: win.WORD,
	nChannels: win.WORD,
	nSamplesPerSec: win.DWORD,
	nAvgBytesPerSec: win.DWORD,
	nBlockAlign: win.WORD,
	wBitsPerSample: win.WORD,
	cbSize: win.WORD,
}

IMMDevice_UUID_STRING :: "D666063F-1587-4E43-81F1-B948E807363F"
IMMDevice_UUID := &IID{0xD666063F, 0x1587, 0x4E43, {0x81, 0xF1, 0xB9, 0x48, 0xE8, 0x07, 0x36, 0x3F}}
IMMDevice_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	Activate: proc "system" (this: ^IMMDevice, iid: win.REFIID, dwClsCtx: win.DWORD, pActivationParams: ^PROPVARIANT, ppInterface: ^rawptr) -> win.HRESULT,
	OpenPropertyStore: proc "system" (this: ^IMMDevice, stgmAccess: win.DWORD, ppProperties: ^^win.IPropertyStore) -> win.HRESULT,
	GetId: proc "system" (this: ^IMMDevice, ppstrId: ^win.LPCWSTR) -> win.HRESULT,
	GetState: proc "system" (this: ^IMMDevice, pdwState: ^win.DWORD) -> win.HRESULT,
}

IMMDevice :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^IMMDevice_VTable,
}

IMMDeviceCollection_UUID_STRING :: "0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"
IMMDeviceCollection_UUID := &IID{0x0BD7A1BE, 0x7A1A, 0x44DB, {0x83, 0x97, 0xCC, 0x53, 0x92, 0x38, 0x7B, 0x5E}}
IMMDeviceCollection_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	GetCount: proc "system" (this: ^IMMDeviceCollection, pcDevices: ^win.UINT) -> win.HRESULT,
	Item: proc "system" (this: ^IMMDeviceCollection, nDevice: win.UINT, ppDevice: ^^IMMDevice) -> win.HRESULT,
}

IMMDeviceCollection :: struct #raw_union {
	#subtype iunknown: IUnknown_VTable,
	using vtable: ^IMMDeviceCollection_VTable,
}

IMMDeviceEnumerator_UUID_STRING :: "A95664D2-9614-4F35-A746-DE8DB63617E6"
IMMDeviceEnumerator_UUID := &IID{0xA95664D2, 0x9614, 0x4F35, {0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6}}
IMMDeviceEnumerator_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	EnumAudioEndpoints: proc "system" (this: ^IMMDeviceEnumerator, dataflow: EDataFlow, dwStateMask: win.DWORD, ppDevices: ^^IMMDeviceCollection) -> win.HRESULT,
	GetDefaultAudioEndpoint: proc "system" (this: ^IMMDeviceEnumerator, dataflow: EDataFlow, role: ERole, ppEndpoint: ^^IMMDevice) -> win.HRESULT,
	GetDevice: proc "system" (this: ^IMMDeviceEnumerator, pwstrId: win.LPCWSTR, ppDevice: ^^IMMDevice) -> win.HRESULT,
	// Don't care about these for now
	RegisterEndpointNotificationCallback: proc "system" (this: ^IMMDeviceEnumerator, unused: rawptr) -> win.HRESULT,
	UnregisterEndpointNotificationCallback: proc "system" (this: ^IMMDeviceEnumerator, unused: rawptr) -> win.HRESULT,
}

IMMDeviceEnumerator :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^IMMDeviceEnumerator_VTable,
}

IAudioClient_UUID_STRING :: "1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"
IAudioClient_UUID := &IID{0x1CB9AD4C, 0xDBFA, 0x4c32, {0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2}}
IAudioClient_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	Initialize: proc "system" (
		this: ^IAudioClient,
		ShareMode: AUDCLNT_SHAREMODE,
		StreamFlags: win.DWORD,
		hnsBufferDuration: REFERENCE_TIME,
		hnsPeriodicity: REFERENCE_TIME,
		pFormat: ^WAVEFORMATEX,
		AudioSessionGuid: win.LPGUID
	) -> win.HRESULT,

	GetBufferSize: proc "system" (this: ^IAudioClient, pNumBufferFrames: ^u32) -> win.HRESULT,
	GetStreamLatency: proc "system" (this: ^IAudioClient, phnsLatency: ^REFERENCE_TIME) -> win.HRESULT,
	GetCurrentPadding: proc "system" (this: ^IAudioClient, pNumPaddingFrames: ^u32) -> win.HRESULT,
	IsFormatSupported: proc "system" (this: ^IAudioClient, ShareMode: AUDCLNT_SHAREMODE, pFormat: ^WAVEFORMATEX, ppClosestMatch: ^WAVEFORMATEX) -> win.HRESULT,
	GetMixFormat: proc "system" (this: ^IAudioClient, ppDeviceFormat: ^^WAVEFORMATEX) -> win.HRESULT,
	GetDevicePeriod: proc "system" (this: ^IAudioClient, phnsDefaultDevicePeriod: ^REFERENCE_TIME, phnsMinimumDevicePeriod: ^REFERENCE_TIME) -> win.HRESULT,
	Start: proc "system" (this: ^IAudioClient, ) -> win.HRESULT,
	Stop: proc "system" (this: ^IAudioClient, ) -> win.HRESULT,
	Reset: proc "system" (this: ^IAudioClient, ) -> win.HRESULT,
	SetEventHandle: proc "system" (this: ^IAudioClient, eventHandle: win.HANDLE) -> win.HRESULT,
	GetService: proc "system" (this: ^IAudioClient, riid: win.REFIID, ppv: ^rawptr) -> win.HRESULT,
}

IAudioClient :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^IAudioClient_VTable,
}

IAudioRenderClient_UUID_STRING :: "F294ACFC-3146-4483-A7BF-ADDCA7C260E2"
IAudioRenderClient_UUID := &IID{0xF294ACFC, 0x3146, 0x4483, {0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2}}
IAudioRenderClient_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	GetBuffer: proc "system" (this: ^IAudioRenderClient, NumFramesRequested: u32, ppData: ^^u8) -> win.HRESULT,
	ReleaseBuffer: proc "system" (this: ^IAudioRenderClient, NumFramesWritten: u32, dwFlags: win.DWORD) -> win.HRESULT,
}

IAudioRenderClient :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^IAudioRenderClient_VTable,
}

ISimpleAudioVolume_UUID_STRING :: "87CE5498-68D6-44E5-9215-6DA47EF883D8"
ISimpleAudioVolume_UUID := &IID{0x87CE5498, 0x68D6, 0x44E5, {0x92, 0x15, 0x6D, 0xA4, 0x7E, 0xF8, 0x83, 0xD8}}
ISimpleAudioVolume_VTable :: struct {
	using iunknown_vtable: IUnknown_VTable,
	SetMasterVolume: proc "system" (this: ^ISimpleAudioVolume, fLevel: f32, EventContext: win.LPCGUID) -> win.HRESULT,
	GetMasterVolume: proc "system" (this: ^ISimpleAudioVolume, pfLevel: ^f32) -> win.HRESULT,
	SetMute: proc "system" (this: ^ISimpleAudioVolume, bMute: win.BOOL, EventContext: win.LPCGUID) -> win.HRESULT,
	GetMute: proc "system" (this: ^ISimpleAudioVolume, pbMute: ^win.BOOL) -> win.HRESULT,
}

ISimpleAudioVolume :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^ISimpleAudioVolume_VTable,
}
