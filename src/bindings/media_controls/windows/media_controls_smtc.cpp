#ifdef _WIN32
#pragma comment(lib, "windowsapp")
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Media.h>
#include <winrt/windows.applicationmodel.h>
#include <winrt/windows.foundation.collections.h>
#include <windows.h>

#include "../media_controls.h"

using namespace winrt::Windows::Media;
using namespace winrt::Windows::Foundation;

static void handle_button_pressed(SystemMediaTransportControls sender,
    SystemMediaTransportControlsButtonPressedEventArgs args);

struct Media_Controls {
	Handler *handler;
	SystemMediaTransportControls smtc;
	void *data;

	Media_Controls(Handler *handler_, void *data_) : handler(handler_), smtc(nullptr), data(data_) {
		smtc = Playback::BackgroundMediaPlayer::Current().SystemMediaTransportControls();
		smtc.IsPlayEnabled(true);
		smtc.IsPauseEnabled(true);
		smtc.IsNextEnabled(true);
		smtc.IsPreviousEnabled(true);
		smtc.ButtonPressed(&handle_button_pressed);
	}

	~Media_Controls() {}
};

static Media_Controls *mc;

static void handle_button_pressed(SystemMediaTransportControls sender,
    SystemMediaTransportControlsButtonPressedEventArgs args) {
	if (!mc) return;

    switch (args.Button()) {
    case SystemMediaTransportControlsButton::Pause:
        mc->handler(mc->data, SIGNAL_PAUSE);
        break;
    case SystemMediaTransportControlsButton::Play:
        mc->handler(mc->data, SIGNAL_PLAY);
        break;
    case SystemMediaTransportControlsButton::Next:
        mc->handler(mc->data, SIGNAL_NEXT);
        break;
    case SystemMediaTransportControlsButton::Previous:
        mc->handler(mc->data, SIGNAL_PREV);
        break;
    }
}

void enable(Handler *handler, void *data) {
	if (mc) return;
	mc = new Media_Controls(handler, data);
}

void disable() {
	if (!mc) return;
	delete mc;
	mc = nullptr;
}

void set_state(int32_t state) {
	if (!mc) return;

	switch (state) {
		case STATE_PAUSED:
		mc->smtc.PlaybackStatus(MediaPlaybackStatus::Paused);
		break;
		case STATE_PLAYING:
		mc->smtc.PlaybackStatus(MediaPlaybackStatus::Playing);
		break;
		case STATE_STOPPED:
		mc->smtc.PlaybackStatus(MediaPlaybackStatus::Stopped);
		break;
	}
}

static void utf8_to_wchar(const char *str, wchar_t *buf, int buf_size) {
    MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, buf_size);
}

void set_metadata(const char *artist, const char *album, const char *title) {
	wchar_t str_buf[128];

	if (!mc) return;

	auto du = mc->smtc.DisplayUpdater();
	du.Type(MediaPlaybackType::Music);
    utf8_to_wchar(artist, str_buf, 128);
    du.MusicProperties().Artist(str_buf);
    utf8_to_wchar(album, str_buf, 128);
    du.MusicProperties().AlbumTitle(str_buf);
    utf8_to_wchar(title, str_buf, 128);
    du.MusicProperties().Title(str_buf);
    du.Update();
}

#endif
