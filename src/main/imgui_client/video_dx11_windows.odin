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
#+private file
package client

import "core:log"
import "src:main/shared"
import "vendor:directx/dxgi"
import dx "vendor:directx/d3d11"
import win "core:sys/windows"
import imgui "src:thirdparty/odin-imgui"
import imgui_dx11 "src:thirdparty/odin-imgui/imgui_impl_dx11"

_dx: struct {
	hwnd:                 win.HWND,
	device:               ^dx.IDevice,
	ctx:                  ^dx.IDeviceContext,
	rtv:                  ^dx.IRenderTargetView,
	swapchain:            ^dxgi.ISwapChain,
	swapchain1:           ^dxgi.ISwapChain1,
}

win32_check :: shared.win32_check

@private
video_shutdown_dx11:: proc() {
	imgui_dx11.Shutdown()
	_destroy_render_target()
	if _dx.swapchain != nil do _dx.swapchain->Release()
	if _dx.ctx != nil do _dx.ctx->Release()
	if _dx.device != nil do _dx.device->Release()
}

@private
video_dx11_init :: proc(hwnd: win.HWND) -> bool {
	_init(hwnd) or_return

	_video_impl_render_frame = proc() {
		clear_color: [4]f32 = {0, 0, 0, 0}
		_dx.ctx->OMSetRenderTargets(1, &_dx.rtv, nil)
		_dx.ctx->ClearRenderTargetView(_dx.rtv, &clear_color)

		if draw_data := imgui.GetDrawData(); draw_data != nil {
			imgui_dx11.RenderDrawData(draw_data)
		}

		result: win.HRESULT
		
		if _dx.swapchain1 != nil {
			_dx.swapchain1->Present(1, {})
		}
		else {
			result = _dx.swapchain->Present(1, {})
		}

		if result == dxgi.STATUS_OCCLUDED {
			return
		}
		else if result == dxgi.ERROR_DEVICE_RESET || result == dxgi.ERROR_DEVICE_REMOVED {
			//_handle_device_lost()
			handle_graphics_device_lost()
		}

		return
	}

	_video_impl_imgui_new_frame = proc() {
		imgui_dx11.NewFrame()
	}


	_video_impl_create_texture = proc(td: Texture_Desc) -> (texture_id: rawptr, ok: bool) {
		tex: ^dx.ITexture2D
		view: ^dx.IShaderResourceView

		desc := dx.TEXTURE2D_DESC {
			ArraySize  = 1,
			MipLevels  = 1,
			Width      = auto_cast td.width,
			Height     = auto_cast td.height,
			Format     = .R8G8B8A8_UNORM,
			SampleDesc = {Count = 1},
			Usage      = .DEFAULT,
			BindFlags  = {.SHADER_RESOURCE},
		}

		init_data := dx.SUBRESOURCE_DATA {
			pSysMem =     auto_cast td.data,
			SysMemPitch = auto_cast(td.width * 4),
		}

		win32_check(_dx.device->CreateTexture2D(&desc, &init_data, &tex)) or_return
		defer tex->Release()
			
		sr := dx.SHADER_RESOURCE_VIEW_DESC {
			Format        = desc.Format,
			ViewDimension = .TEXTURE2D,
			Texture2D     = {MipLevels = 1},
		}

		win32_check(_dx.device->CreateShaderResourceView(tex, &sr, &view))

		return view, true
	}
	
	_video_impl_destroy_texture = proc(tex: rawptr) {
		if tex != nil {
			view := cast(^dx.IShaderResourceView) tex
			view->Release()
		}
	}

	/*_video_impl_update_texture = proc(tex: rawptr, offset: [2]int, size: [2]int, data: rawptr) -> bool {
		if tex == nil do return false

		resource: ^dx11.IResource
		view: ^dx11.IShaderResourceView = auto_cast tex

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
	}*/

	_video_impl_get_texture_imgui_ref = proc(tex: rawptr) -> (imgui.TextureRef, bool) {
		return imgui.TextureRef {
			_TexID = cast(imgui.TextureID) uintptr(tex)
		}, true
	}

	_video_impl_resize_swapchain = proc(width, height: int) {
		_destroy_render_target()
		_dx.swapchain->ResizeBuffers(2, auto_cast width, auto_cast height, .UNKNOWN, {})
		_create_render_target()
	}

	return true
}

@private
video_dx11_resize_window :: proc(w, h: int) {
	_destroy_render_target()
	_dx.swapchain->ResizeBuffers(2, auto_cast w, auto_cast h, .UNKNOWN, {})
	_create_render_target()
}

_init :: proc(hwnd: win.HWND, from_device_reset := false) -> bool {
	_dx.hwnd = hwnd

	swapchain := dxgi.SWAP_CHAIN_DESC {
		BufferCount  = 2,
		Flags        = {.ALLOW_MODE_SWITCH},
		BufferUsage  = {.RENDER_TARGET_OUTPUT},
		OutputWindow = hwnd,
		SampleDesc   = {Count = 1},
		Windowed     = true,
		SwapEffect   = .FLIP_SEQUENTIAL,
		BufferDesc   = {
			Format      = .R8G8B8A8_UNORM,
			RefreshRate = {Numerator = 60, Denominator = 1},
		},
	}

	feature_levels := []dx.FEATURE_LEVEL {
		._11_1,
		._11_0,
	}

	selected_feature_level: dx.FEATURE_LEVEL

	win32_check(
		dx.CreateDeviceAndSwapChain(
			nil, .HARDWARE, nil, {},
			raw_data(feature_levels), auto_cast len(feature_levels), dx.SDK_VERSION,
			&swapchain, &_dx.swapchain, &_dx.device,
			&selected_feature_level, &_dx.ctx
		)
	) or_return

	if selected_feature_level == ._11_1 {
		fac: ^dxgi.IFactory2

		log.debug("Using DX11.1 ISwapchain1")

		swapchain1 := dxgi.SWAP_CHAIN_DESC1 {
			BufferCount = 2,
			BufferUsage = {.RENDER_TARGET_OUTPUT},
			Flags       = {.ALLOW_MODE_SWITCH},
			Format      = .R8G8B8A8_UNORM,
			SampleDesc  = {Count = 1},
			SwapEffect  = .FLIP_SEQUENTIAL,
		}

		_dx.swapchain->Release()

		win32_check(dxgi.CreateDXGIFactory2({}, dxgi.IFactory2_UUID, auto_cast &fac)) or_return

		fac->CreateSwapChainForHwnd(_dx.device, hwnd, &swapchain1, nil, nil, &_dx.swapchain1)

		_dx.swapchain = _dx.swapchain1
	}

	imgui_dx11.Init(_dx.device, _dx.ctx) or_return
	_create_render_target()

	return true
}

@(private="file")
_create_render_target :: proc() -> bool {
	texture: ^dx.ITexture2D
	win32_check(_dx.swapchain->GetBuffer(0, dx.ITexture2D_UUID, cast(^rawptr) &texture)) or_return

	if texture == nil {
		_dx.rtv = nil
		return false
	}
	defer texture->Release()

	win32_check(_dx.device->CreateRenderTargetView(texture, nil, &_dx.rtv)) or_return

	return true
}

@(private="file")
_destroy_render_target :: proc() {
	if _dx.rtv != nil {
		_dx.rtv->Release()
		_dx.rtv = nil
	}
}
