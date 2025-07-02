#+private
package client

// Enums work too
_Preference_String :: [64]u8
_Preference_Path :: [512]u8
_Preference_Int :: int
_Preference_Float :: f32
_Preference_Bool :: bool

_Preferences :: struct {
	theme: _Preference_String `editor_name:Theme`,
	background: _Preference_Path `editor_name:Background`,
	crop_album_art: _Preference_Bool `editor_name:Crop album art`,

	spectrum_bands: _Preference_Int `hide`,
	spectrum_mode: _Spectrum_Display_Mode `hide`,
}
