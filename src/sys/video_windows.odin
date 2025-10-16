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

import "core:log"
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
	repeat_sampler: ^dx11.ISamplerState,
}

video_create_texture :: proc(data: rawptr, width, height: int) -> (texture_id: imgui.TextureID, ok: bool) {
	staging: ^dx11.ITexture2D
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
	
	win32_check(d3d.device->CreateTexture2D(&desc, nil, &staging)) or_return
	defer staging->Release()
	
	desc.Usage = .DEFAULT
	desc.CPUAccessFlags = {}
	win32_check(d3d.device->CreateTexture2D(&desc, nil, &texture)) or_return
	defer texture->Release()

	mapped: dx11.MAPPED_SUBRESOURCE
	win32_check(d3d.ctx->Map(staging, 0, .WRITE_DISCARD, {}, &mapped)) or_return

	// If the target pitch is not the same we need to manually
	// copy each row
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

video_create_dynamic_texture :: proc(width, height: int) -> (id: imgui.TextureID, ok: bool) {
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
		Usage = .DEFAULT,
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

video_update_dynamic_texture :: proc(tex: imgui.TextureID, offset: [2]int, size: [2]int, data: rawptr) -> bool {
	if tex == 0 {return false}

	resource: ^dx11.IResource
	view: ^dx11.IShaderResourceView = auto_cast uintptr(tex)

	view->GetResource(&resource)
	box := dx11.BOX {
		top = auto_cast offset.y,
		right = auto_cast(offset.x + size.x),
		left = auto_cast offset.x,
		bottom = auto_cast(offset.y + size.y),
		back = 1,
	}
	d3d.ctx->UpdateSubresource(resource, 0, &box, data, auto_cast size.x * 4, 0)

	return true
}

video_destroy_texture :: proc(texture: imgui.TextureID) {
	if texture != 0 {
		view := cast(^dx11.IShaderResourceView) uintptr(texture)
		view->Release()
	}
}

video_render_imgui_draw_data :: proc(draw_data: ^imgui.DrawData) {
	imgui_dx11.RenderDrawData(draw_data)
}

video_invalidate_imgui_objects :: proc() {
	imgui_dx11.InvalidateDeviceObjects()
}

video_create_imgui_objects :: proc() {
	imgui_dx11.CreateDeviceObjects()
}

video_imgui_callback_override_sampler :: proc "c" (drawlist: ^imgui.DrawList, cmd: ^imgui.DrawCmd) {
	render_state := cast(^imgui_dx11.RenderState) imgui.GetPlatformIO().Renderer_RenderState
	//render_state.SamplerDefault = d3d.repeat_sampler
	render_state.DeviceContext->PSSetSamplers(0, 1, &d3d.repeat_sampler)
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

	sampler_desc := dx11.SAMPLER_DESC {
		Filter = .COMPARISON_MIN_MAG_MIP_LINEAR,
		AddressW = .WRAP,
		AddressV = .WRAP,
		AddressU = .WRAP,
		ComparisonFunc = .ALWAYS,
	}

	win32_check(d3d.device->CreateSamplerState(&sampler_desc, &d3d.repeat_sampler)) or_return

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

