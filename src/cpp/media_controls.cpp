#ifdef _WIN32
#pragma comment(lib, "windowsapp")
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Media.h>
#include <winrt/windows.applicationmodel.h>
#include <winrt/windows.foundation.collections.h>
#include <windows.h>

#define ARRAY_LENGTH(arr) (sizeof(arr)/sizeof(arr[0]))

typedef void Event_Handler_Proc(int event);

using namespace winrt::Windows::Media;
using namespace winrt::Windows::Foundation;
static SystemMediaTransportControls g_smtc(nullptr);
static Event_Handler_Proc *handler;

enum {
	EVENT_PAUSE,
	EVENT_PLAY,
	EVENT_PREV,
	EVENT_NEXT,
};

enum {
    STATUS_STOPPED,
    STATUS_PAUSED,
    STATUS_PLAYING,
};


static void handle_button_pressed(SystemMediaTransportControls sender,
    SystemMediaTransportControlsButtonPressedEventArgs args) {
    switch (args.Button()) {
    case SystemMediaTransportControlsButton::Pause:
        handler(EVENT_PAUSE);
        break;
    case SystemMediaTransportControlsButton::Play:
        handler(EVENT_PLAY);
        break;
    case SystemMediaTransportControlsButton::Next:
        handler(EVENT_NEXT);
        break;
    case SystemMediaTransportControlsButton::Previous:
        handler(EVENT_PREV);
        break;
    }
}

static void utf8_to_wchar(const char *str, wchar_t *buf, int buf_size) {
    MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, buf_size);
}

extern "C" void media_controls_set_status(int status) {
    switch (status) {
    case STATUS_PAUSED:
        g_smtc.PlaybackStatus(MediaPlaybackStatus::Paused);
        break;
    case STATUS_PLAYING:
        g_smtc.PlaybackStatus(MediaPlaybackStatus::Playing);
        break;
    default:
        g_smtc.PlaybackStatus(MediaPlaybackStatus::Stopped);
        break;
    }
}

extern "C" void media_controls_set_metadata(const char *album, const char *artist, const char *title) {
    auto updater = g_smtc.DisplayUpdater();
    updater.Type(MediaPlaybackType::Music);
   
    // Strings need to be converted to utf16
    wchar_t str_buf[128];
    utf8_to_wchar(artist, str_buf, ARRAY_LENGTH(str_buf));
    updater.MusicProperties().Artist(str_buf);
    utf8_to_wchar(album, str_buf, ARRAY_LENGTH(str_buf));
    updater.MusicProperties().AlbumTitle(str_buf);
    utf8_to_wchar(title, str_buf, ARRAY_LENGTH(str_buf));
    updater.MusicProperties().Title(str_buf);
    updater.Update();
}

extern "C" bool media_controls_install_handler(Event_Handler_Proc *handler_proc) {
	handler = handler_proc;
    g_smtc = Playback::BackgroundMediaPlayer::Current().SystemMediaTransportControls();
    g_smtc.IsPlayEnabled(true);
    g_smtc.IsPauseEnabled(true);
    g_smtc.IsNextEnabled(true);
    g_smtc.IsPreviousEnabled(true);

    g_smtc.ButtonPressed(&handle_button_pressed);

    return true;
}
#endif
