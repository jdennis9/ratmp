package portaudio

import "core:c"

when ODIN_OS == .Linux {
	foreign import lib "system:portaudio"
}
else {
	foreign import lib "portaudio.lib"
}

ErrorCode :: enum c.int {
	NoError = 0,
	paNotInitialized = -10000,
    paUnanticipatedHostError,
    paInvalidChannelCount,
    paInvalidSampleRate,
    paInvalidDevice,
    paInvalidFlag,
    paSampleFormatNotSupported,
    paBadIODeviceCombination,
    paInsufficientMemory,
    paBufferTooBig,
    paBufferTooSmall,
    paNullCallback,
    paBadStreamPtr,
    paTimedOut,
    paInternalError,
    paDeviceUnavailable,
    paIncompatibleHostApiSpecificStreamInfo,
    paStreamIsStopped,
    paStreamIsNotStopped,
    paInputOverflowed,
    paOutputUnderflowed,
    paHostApiNotFound,
    paInvalidHostApi,
    paCanNotReadFromACallbackStream,
    paCanNotWriteToACallbackStream,
    paCanNotReadFromAnOutputOnlyStream,
    paCanNotWriteToAnInputOnlyStream,
    paIncompatibleStreamHostApi,
    paBadBufferPtr
}

DeviceIndex :: c.int
NoDevice :: cast(DeviceIndex)-1
Time :: f64
SampleFormat :: c.ulong
StreamFlags :: c.ulong
StreamCallbackFlags :: c.ulong

SampleFormat_Float32 :: 0x00000001

StreamCallbackTimeInfo :: struct {
    inputBufferAdcTime: Time,
    currentTime: Time,
    outputBufferDacTime: Time,
}

StreamCallbackResult :: enum c.int {
    Continue,
    Complete,
    Abort,
}

StreamCallback :: #type proc "c" (
    input, output: rawptr,
    frameCount: c.ulong,
    timeInfo: ^StreamCallbackTimeInfo,
    statusFlags: StreamCallbackFlags,
    userData: rawptr,
) -> StreamCallbackResult

DeviceInfo :: struct {
    structVersion: c.int,
    name: cstring,
    hostApi: c.int,
    maxInputChannels: c.int,
    maxOutputChannels: c.int,
    defaultLowInputLatency: Time,
    defaultLowOutputLatency: Time,
    defaultHighInputLatency: Time,
    defaultHighOutputLatency: Time,
    defaultSampleRate: f64,
}

Stream :: distinct rawptr

@(link_prefix="Pa_")
foreign lib {
	GetErrorText :: proc(code: ErrorCode) -> cstring ---
    Initialize :: proc() -> ErrorCode ---
    Terminate :: proc() -> ErrorCode ---
    GetDeviceCount :: proc() -> DeviceIndex ---
    GetDefaultOutputDevice :: proc() -> DeviceIndex ---
    GetDeviceInfo :: proc(device: DeviceIndex) -> ^DeviceInfo ---
    OpenDefaultStream :: proc(
        stream: ^Stream,
        numInputChannels: c.int,
        numOutputChannels: c.int,
        sampleFormat: SampleFormat,
        sampleRate: f64,
        framesPerBuffer: c.ulong,
        callback: StreamCallback,
        userData: rawptr,
    ) -> ErrorCode ---
    CloseStream :: proc(stream: Stream) -> ErrorCode ---
    StartStream :: proc(stream: Stream) -> ErrorCode ---
    StopStream :: proc(stream: Stream) -> ErrorCode ---
    AbortStream :: proc(stream: Stream) -> ErrorCode ---
}


