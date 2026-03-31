#+private file
package main

import "vendor:directx/dxgi"
import dx "vendor:directx/d3d11"
import win "core:sys/windows"
import imgui "src:thirdparty/odin-imgui"
import imgui_dx11 "src:thirdparty/odin-imgui/imgui_impl_dx11"

_dx: struct {
	hwnd: win.HWND,
	device: ^dx.IDevice,
	ctx: ^dx.IDeviceContext,
	rtv: ^dx.IRenderTargetView,
	swapchain: ^dxgi.ISwapChain,
}

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
		clear_color: [4]f32 = {0, 0, 0, 1}
		_dx.ctx->OMSetRenderTargets(1, &_dx.rtv, nil)
		_dx.ctx->ClearRenderTargetView(_dx.rtv, &clear_color)

		if draw_data := imgui.GetDrawData(); draw_data != nil {
			imgui_dx11.RenderDrawData(draw_data)
		}

		result := _dx.swapchain->Present(1, {})

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
		staging: ^dx.ITexture2D
		texture: ^dx.ITexture2D
		view: ^dx.IShaderResourceView

		//if data == nil do return _create_dynamic_texture(width, height)

		desc := dx.TEXTURE2D_DESC {
			Width = auto_cast td.width,
			Height = auto_cast td.height,
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
		
		win32_check(_dx.device->CreateTexture2D(&desc, nil, &staging)) or_return
		defer staging->Release()
		
		desc.Usage = .DEFAULT
		desc.CPUAccessFlags = {}
		win32_check(_dx.device->CreateTexture2D(&desc, nil, &texture)) or_return
		defer texture->Release()

		mapped: dx.MAPPED_SUBRESOURCE
		win32_check(_dx.ctx->Map(staging, 0, .WRITE_DISCARD, {}, &mapped)) or_return

		// If the target pitch is not the same we need to manually
		// copy each row
		pitch := 4 * td.width
		if mapped.RowPitch != u32(pitch) {
			out := cast([^]u8) mapped.pData
			pixels := cast([^]u8) td.data
			offset := 0

			for row in 0..<td.height {
				row_start := row * int(mapped.RowPitch)
				copy(out[row_start:][:mapped.RowPitch], pixels[offset:][:pitch])

				offset += pitch
			}
		}
		else {
			out := cast([^]u8) mapped.pData
			pixels := cast([^]u8) td.data
			size := td.width * td.height * 4

			copy(out[:size], pixels[:size])
		}

		_dx.ctx->Unmap(staging, 0)
		_dx.ctx->CopyResource(texture, staging)

		sr := dx.SHADER_RESOURCE_VIEW_DESC {
			Format = desc.Format,
			ViewDimension = .TEXTURE2D,
			Texture2D = {
				MipLevels = 1,
			},
		}

		win32_check(_dx.device->CreateShaderResourceView(texture, &sr, &view)) or_return

		texture_id = view
		ok = true
		return
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
		_dx.swapchain->ResizeBuffers(1, auto_cast width, auto_cast height, .UNKNOWN, {})
		_create_render_target()
	}

	return true
}

@private
video_dx11_resize_window :: proc(w, h: int) {
	_destroy_render_target()
	_dx.swapchain->ResizeBuffers(1, auto_cast w, auto_cast h, .UNKNOWN, {})
	_create_render_target()
}

_init :: proc(hwnd: win.HWND, from_device_reset := false) -> bool {
	_dx.hwnd = hwnd

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

	/*if !from_device_reset do */imgui_dx11.Init(_dx.device, _dx.ctx) or_return
	_create_render_target()

	/*sampler_desc := dx11.SAMPLER_DESC {
		Filter = .COMPARISON_MIN_MAG_MIP_LINEAR,
		AddressW = .WRAP,
		AddressV = .WRAP,
		AddressU = .WRAP,
		ComparisonFunc = .ALWAYS,
	}

	win32_check(_dx.device->CreateSamplerState(&sampler_desc, &_dx.repeat_sampler)) or_return*/

	return true
}

@(private="file")
_create_render_target :: proc() -> bool {
	texture: ^dx.ITexture2D
	_dx.swapchain->GetBuffer(0, dx.ITexture2D_UUID, cast(^rawptr) &texture)
	if texture == nil {
		_dx.rtv = nil
		return false
	}
	_dx.device->CreateRenderTargetView(texture, nil, &_dx.rtv)
	texture->Release()

	return true
}

@(private="file")
_destroy_render_target :: proc() {
	if _dx.rtv != nil {
		_dx.rtv->Release()
		_dx.rtv = nil
	}
}
