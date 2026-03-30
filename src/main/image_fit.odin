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

image_fit :: proc(
	policy: Image_Fit_Policy, target: Rect, size: [2]f32
) -> (rect: Rect, uv: Rect) {
	target_size := target.max - target.min
	ratio := target_size / size

	switch policy {
	case .Fill:
		r := max(ratio.x, ratio.y)
		rect.min = target.min
		rect.max = target.min + (size * r)
		uv = {{0, 0}, {1, 1}}
		offset := (target_size - (size * r)) * 0.5
		rect.min += offset
		rect.max += offset

	case .Stretch:
		return target, {{0, 0}, {1, 1}}

	case .Center:
		rect.min = target.min
		rect.max = target.min + size
		uv = {{0, 0}, {1, 1}}
		offset := (target_size - size) * 0.5
		rect.min += offset
		rect.max += offset

	case .Fit:
		r := min(ratio.x, ratio.y)
		rect.min = target.min
		rect.max = target.min + (size * r)
		uv = {{0, 0}, {1, 1}}
		offset := (target_size - (size * r)) * 0.5
		rect.min += offset
		rect.max += offset
	}


	return
}
