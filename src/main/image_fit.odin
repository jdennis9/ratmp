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
package main

Rect :: struct {min, max: [2]f32}

Image_Fit_Policy :: enum {
	Fill,
	Stretch,
	Fit,
	Center,
}

rect_center :: proc(r: Rect) -> [2]f32 {
	s := r.max - r.min
	return r.min + s * 0.5
}

image_fit_clip :: proc(
	policy: Image_Fit_Policy, target: Rect, size: [2]f32
) -> (rect: Rect) {
	target_size := target.max - target.min
	ratio := target_size / size

	switch policy {
	case .Fill:
		r := max(ratio.x, ratio.y)
		rect.min = target.min
		rect.max = target.min + (size * r)
		offset := (target_size - (size * r)) * 0.5
		rect.min += offset
		rect.max += offset

	case .Stretch:
		return target

	case .Center:
		rect.min = target.min
		rect.max = target.min + size
		offset := (target_size - size) * 0.5
		rect.min += offset
		rect.max += offset

	case .Fit:
		r := min(ratio.x, ratio.y)
		rect.min = target.min
		rect.max = target.min + (size * r)
		offset := (target_size - (size * r)) * 0.5
		rect.min += offset
		rect.max += offset
	}

	return
}

image_fit_uv :: proc(
	policy: Image_Fit_Policy, target: Rect, size: [2]f32
) -> (uv: Rect) {
	rect := image_fit_clip(policy, target, size)
	rect_size := rect.max - rect.min
	uv.min = (target.min / rect_size) - (rect.min / rect_size)
	uv.max = uv.min + (target.max / rect_size)
	return
}
