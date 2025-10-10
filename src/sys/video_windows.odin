/*
    RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025 Jamie Dennis

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
package sys

import "core:slice"
import "core:mem"
import win "core:sys/windows"
import dx11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"

import imgui "src:thirdparty/odin-imgui"
import imgui_dx11 "src:thirdparty/odin-imgui/imgui_impl_dx11"

@(private="file")
d3d: struct {
	device: ^dx11.IDevice,
	ctx: ^dx11.IDeviceContext,
	render_target: ^dx11.IRenderTargetView,
	swapchain: ^dxgi.ISwapChain,
}

imgui_create_texture :: proc(data: rawptr, width, height: int) -> (texture_id: imgui.TextureID, ok: bool) {
	staging: ^dx11.ITexture2D
	texture: ^dx11.ITexture2D
	view: ^dx11.IShaderResourceView

	/*desc := dx11.TEXTURE2D_DESC {
		Width = auto_cast width,
		Height = auto_cast height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		Usage = .DEFAULT,
		BindFlags = {.SHADER_RESOURCE},
		CPUAccessFlags = {.WRITE},
	}

	sr := dx11.SHADER_RESOURCE_VIEW_DESC {
		Format = desc.Format,
		ViewDimension = .TEXTURE2D,
		Texture2D = {
			MipLevels = 1,
		},
	}

	init_data: dx11.SUBRESOURCE_DATA
	init_data.pSysMem = data
	init_data.SysMemPitch = auto_cast width * 4

	win32_check(_win32.d3d.device->CreateTexture2D(&desc, &init_data, &texture)) or_return
	win32_check(_win32.d3d.device->CreateShaderResourceView(texture, &sr, &view)) or_return
	return auto_cast view, true*/

	desc := dx11.TEXTURE2D_DESC {
		Width = auto_cast width,
		Height = auto_cast height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		Usage = .DYNAMIC,
		BindFlags = {.SHADER_RESOURCE},
		CPUAccessFlags = {.WRITE},
	}
	
	win32_check(d3d.device->CreateTexture2D(&desc, nil, &staging)) or_return
	defer staging->Release()
	
	desc.Usage = .DEFAULT
	desc.CPUAccessFlags = {}
	win32_check(d3d.device->CreateTexture2D(&desc, nil, &texture)) or_return
	defer texture->Release()

	mapped: dx11.MAPPED_SUBRESOURCE
	win32_check(d3d.ctx->Map(staging, 0, .WRITE_DISCARD, {}, &mapped)) or_return

	// If the target pitch is not the same we need to manually
	// copy each pixel
	pitch := 4 * width
	if mapped.RowPitch != u32(pitch) {
		out := cast([^]u8) mapped.pData
		pixels := cast([^]u8) data
		offset := 0

		for row in 0..<height {
			row_start := row * int(mapped.RowPitch)
			copy(out[row_start:][:mapped.RowPitch], pixels[offset:][:pitch])

			offset += pitch
		}
	}
	else {
		out := cast([^]u8) mapped.pData
		pixels := cast([^]u8) data
		size := width * height * 4

		copy(out[:size], pixels[:size])
	}

	d3d.ctx->Unmap(staging, 0)
	d3d.ctx->CopyResource(texture, staging)

	sr := dx11.SHADER_RESOURCE_VIEW_DESC {
		Format = desc.Format,
		ViewDimension = .TEXTURE2D,
		Texture2D = {
			MipLevels = 1,
		},
	}

	win32_check(d3d.device->CreateShaderResourceView(texture, &sr, &view)) or_return

	texture_id = auto_cast uintptr(view)
	ok = true
	return
}

imgui_create_dynamic_texture :: proc(width, height: int) -> (id: imgui.TextureID, ok: bool) {
	texture: ^dx11.ITexture2D
	view: ^dx11.IShaderResourceView

	desc := dx11.TEXTURE2D_DESC {
		Width = auto_cast width,
		Height = auto_cast height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		Usage = .DYNAMIC,
		BindFlags = {.SHADER_RESOURCE},
		CPUAccessFlags = {.WRITE},
	}

	win32_check(d3d.device->CreateTexture2D(&desc, nil, &texture)) or_return
	defer texture->Release()

	sr := dx11.SHADER_RESOURCE_VIEW_DESC {
		Format = desc.Format,
		ViewDimension = .TEXTURE2D,
		Texture2D = {
			MipLevels = 1,
		},
	}

	win32_check(d3d.device->CreateShaderResourceView(texture, &sr, &view)) or_return
	id = auto_cast(uintptr(view))
	ok = true

	return
}

imgui_update_dynamic_texture :: proc(tex: imgui.TextureID, offset: [2]int, size: [2]int, data: rawptr) -> bool {
	if tex == 0 {return false}

	resource: ^dx11.IResource
	view: ^dx11.IShaderResourceView = auto_cast uintptr(tex)
	mapped: dx11.MAPPED_SUBRESOURCE

	dst_box := dx11.BOX {
		left = auto_cast offset.x,
		right = auto_cast (offset.x + size.x),
		top = auto_cast offset.y,
		bottom = auto_cast (offset.y + size.y),
		front = 0,
		back = 1,
	}

	view->GetResource(&resource)
	if resource == nil {
		return false
	}

	subresource := dx11.CalcSubresource(0, 0, 0)

	win32_check(d3d.ctx->Map(resource, subresource, .WRITE_DISCARD, {}, &mapped)) or_return
	defer d3d.ctx->Unmap(resource, subresource)

	row_count := u32(size.y)
	y_offset := u32(offset.y)
	x_offset := u32(offset.x) * 4
	in_row_pitch := u32(size.x * 4)

	for i in 0..<row_count {
		row_out := (cast([^]u8)mapped.pData)[mapped.RowPitch * (y_offset + i) + x_offset:][:in_row_pitch]
		row_in := (cast([^]u8)data)[in_row_pitch * i:][:in_row_pitch]

		mem.copy(raw_data(row_out), raw_data(row_in), int(in_row_pitch))
	}

	return true
}

imgui_destroy_texture :: proc(texture: imgui.TextureID) {
	if texture != 0 {
		view := cast(^dx11.IShaderResourceView) uintptr(texture)
		view->Release()
	}
}

imgui_render_draw_data :: proc(draw_data: ^imgui.DrawData) {
	imgui_dx11.RenderDrawData(draw_data)
}

imgui_invalidate_objects :: proc() {
	imgui_dx11.InvalidateDeviceObjects()
}

imgui_create_objects :: proc() {
	imgui_dx11.CreateDeviceObjects()
}

_dx11_init :: proc(hwnd: win.HWND) -> bool {
	swapchain := dxgi.SWAP_CHAIN_DESC {
		BufferCount = 2,
		BufferDesc = {
			Format = .R8G8B8A8_UNORM,
			RefreshRate = {Numerator = 60, Denominator = 1},
		},
		Flags = {.ALLOW_MODE_SWITCH},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		OutputWindow = hwnd,
		SampleDesc = {
			Count = 1,
		},
		Windowed = true,
		SwapEffect = .DISCARD,
	}

	feature_levels := []dx11.FEATURE_LEVEL {
		._11_1,
		._11_0,
	}

	selected_feature_level: dx11.FEATURE_LEVEL

	win32_check(
		dx11.CreateDeviceAndSwapChain(
			nil, .HARDWARE, nil, {},
			raw_data(feature_levels), auto_cast len(feature_levels), dx11.SDK_VERSION,
			&swapchain, &d3d.swapchain, &d3d.device,
			&selected_feature_level, &d3d.ctx
		)
	) or_return

	imgui_dx11.Init(d3d.device, d3d.ctx) or_return
	_dx11_create_render_target()

	return true
}

_dx11_destroy :: proc() {
	imgui_dx11.Shutdown()
	_dx11_destroy_render_target()
	if d3d.swapchain != nil {d3d.swapchain->Release()}
	if d3d.ctx != nil {d3d.ctx->Release()}
	if d3d.device != nil {d3d.device->Release()}
}

_dx11_clear_buffer :: proc() {
	clear_color: [4]f32 = {0, 0, 0, 1}
	d3d.ctx->OMSetRenderTargets(1, &d3d.render_target, nil)
	d3d.ctx->ClearRenderTargetView(d3d.render_target, &clear_color)
}

_dx11_present :: proc() -> (obscured: bool) {
	return d3d.swapchain->Present(1, {}) == dxgi.STATUS_OCCLUDED
}

_dx11_create_render_target :: proc() {
	texture: ^dx11.ITexture2D
	d3d.swapchain->GetBuffer(0, dx11.ITexture2D_UUID, cast(^rawptr) &texture)
	if texture == nil {
		d3d.render_target = nil
		return
	}
	d3d.device->CreateRenderTargetView(texture, nil, &d3d.render_target)
	texture->Release()
}

_dx11_destroy_render_target :: proc() {
	if d3d.render_target != nil {
		d3d.render_target->Release()
		d3d.render_target = nil
	}
}

_dx11_resize_swapchain :: proc(width, height: int) {
	_dx11_destroy_render_target()
	d3d.swapchain->ResizeBuffers(1, auto_cast width, auto_cast height, .UNKNOWN, {})
	_dx11_create_render_target()
}

