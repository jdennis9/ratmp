/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
package player

import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strconv"

@require_results
parse_config :: proc(m: map[string]string) -> Config {
	cfg := CONFIG_DEFAULTS

	for k, v in m {
		switch k {
		case "EnableReplayGain":
			cfg.enable_replaygain = strconv.parse_bool(v) or_break
		case "ReplayGainPreGain":
			cfg.replaygain_pregain = strconv.parse_f32(v) or_break
			cfg.replaygain_pregain = clamp(cfg.replaygain_pregain, -16, 16)
		case "ReplayGainPreference":
			cfg.replaygain_preference = reflect.enum_from_name(ReplayGain_Mode, v) or_break
		}
	}

	return cfg
}

write_config :: proc(c: Config, m: ^map[string]string, allocator: mem.Allocator) {
	m["EnableReplayGain"]     = fmt.aprint(c.enable_replaygain,     allocator=allocator)
	m["ReplayGainPreGain"]    = fmt.aprint(c.replaygain_pregain,    allocator=allocator)
	m["ReplayGainPreference"] = fmt.aprint(c.replaygain_preference, allocator=allocator)
}

