/*
	RAT MP: A lightweight graphical music player
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
package video_dx11;

import "core:log";
import "core:time";

import win "core:sys/windows";
import dx "vendor:directx/d3d11";
import dxgi "vendor:directx/dxgi";
import imgui "libs:odin-imgui";
import imgui_dx11 "libs:odin-imgui/imgui_impl_dx11";
import imgui_win32 "libs:odin-imgui/imgui_impl_win32";

import com "..";

@private
this : struct {
	device: ^dx.IDevice,
	device_ctx: ^dx.IDeviceContext,
	swapchain: ^dxgi.ISwapChain,
	render_target: ^dx.IRenderTargetView,
}

@private
_create_render_target :: proc() {
	texture: ^dx.ITexture2D;

	this.swapchain->GetBuffer(0, dx.ITexture2D_UUID, cast(^rawptr) &texture);

	if texture == nil {
		this.render_target = nil;
		return;
	}

	this.device->CreateRenderTargetView(texture, nil, &this.render_target);
	texture->Release();
}

@private
_destroy_render_target :: proc() {
	if this.render_target != nil {
		this.render_target->Release();
		this.render_target = nil;
	}
}

init_for_windows :: proc(hwnd: win.HWND) -> bool {
	log.debug("Setting up DX11...");

	swapchain := dxgi.SWAP_CHAIN_DESC {
		BufferCount = 2,
		BufferDesc = {
			Format = .R8G8B8A8_UNORM,
			RefreshRate = {
				Numerator = 60,
				Denominator = 1,
			},
		},
		Flags = {.ALLOW_MODE_SWITCH},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		OutputWindow = hwnd,
		SampleDesc = {
			Count = 1,
		},
		Windowed = true,
		SwapEffect = .DISCARD,
	};

	feature_levels := []dx.FEATURE_LEVEL {
		dx.FEATURE_LEVEL._11_1,
		dx.FEATURE_LEVEL._11_0,
	};

	selected_feature_level: dx.FEATURE_LEVEL;
	result: win.HRESULT;

	result = dx.CreateDeviceAndSwapChain(nil, .HARDWARE, nil, {}, 
		raw_data(feature_levels), auto_cast len(feature_levels), dx.SDK_VERSION,
		&swapchain, &this.swapchain, &this.device, &selected_feature_level, &this.device_ctx);
	
	if result != win.S_OK {
		log.error("Failed to initialize DX11");
		return false;
	}

	_create_render_target();

	imgui_win32.Init(hwnd);
	imgui_dx11.Init(this.device, this.device_ctx);

	com.impl.create_texture = create_texture;
	com.impl.destroy_texture = destroy_texture;
	com.impl.invalidate_imgui_objects = invalidate_imgui_objects;
	com.impl.create_imgui_objects = create_imgui_objects;

	return true;
}

shutdown_for_windows :: proc() {
	_destroy_render_target();
	imgui_dx11.Shutdown();
	imgui_win32.Shutdown();
	if this.swapchain != nil {
		this.swapchain->Release();
	}
	if this.device_ctx != nil {
		this.device_ctx->Release();
	}
	if this.device != nil {
		this.device->Release();
	}
}

shutdown_imgui :: proc() {
	imgui_dx11.Shutdown();
}

begin_frame :: proc() -> bool {
	clear_color: [4]f32 = {0, 0, 0, 1};
	this.device_ctx->OMSetRenderTargets(1, &this.render_target, nil);
	this.device_ctx->ClearRenderTargetView(this.render_target, &clear_color);

	imgui_dx11.NewFrame();
	imgui_win32.NewFrame();
	imgui.NewFrame();

	return true;
}

// Returns false if the window is not visible
present :: proc() -> (visible: bool) {
	imgui.Render();

	draw_data := imgui.GetDrawData();
	if draw_data != nil {
		imgui_dx11.RenderDrawData(draw_data);
	}

	return this.swapchain->Present(1, {}) != dxgi.STATUS_OCCLUDED;
}

resize_window :: proc(w, h: int) {
	_destroy_render_target();
	this.swapchain->ResizeBuffers(1, auto_cast w, auto_cast h, .UNKNOWN, {});
	_create_render_target();
}

invalidate_imgui_objects :: proc() {
	imgui_dx11.InvalidateDeviceObjects();
}

create_imgui_objects :: proc() {
	imgui_dx11.CreateDeviceObjects();
}

create_texture :: proc(width, height: int, data: rawptr) -> (out: com.Texture, ok: bool) {
	staging: ^dx.ITexture2D;
	texture: ^dx.ITexture2D;
	view: ^dx.IShaderResourceView;

	desc := dx.TEXTURE2D_DESC {
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
	};
	
	this.device->CreateTexture2D(&desc, nil, &staging);
	defer staging->Release();
	
	desc.Usage = .DEFAULT;
	desc.CPUAccessFlags = {};
	this.device->CreateTexture2D(&desc, nil, &texture);
	defer texture->Release();

	mapped: dx.MAPPED_SUBRESOURCE;
	this.device_ctx->Map(staging, 0, .WRITE_DISCARD, {}, &mapped);
	// If the target pitch is not the same we need to manually
	// copy each pixel
	pitch := 4 * width;
	if mapped.RowPitch != u32(pitch) {
		out := cast([^]u8) mapped.pData;
		pixels := cast([^]u8) data;
		offset := 0;

		log.debug("Using manual copy (row pitch (in, out) =", pitch, mapped.RowPitch, ")");

		timer: time.Stopwatch;
		time.stopwatch_start(&timer);

		for row in 0..<height {
			row_start := row * int(mapped.RowPitch);
			copy(out[row_start:][:mapped.RowPitch], pixels[offset:][:pitch]);

			offset += pitch;
		}

		time.stopwatch_stop(&timer);

		log.debug("Image copy:", time.duration_milliseconds(time.stopwatch_duration(timer)), "ms");
	}
	else {
		out := cast([^]u8) mapped.pData;
		pixels := cast([^]u8) data;
		size := width * height * 4;

		log.debug("Using direct copy");

		copy(out[:size], pixels[:size]);
	}
	this.device_ctx->Unmap(staging, 0);

	this.device_ctx->CopyResource(texture, staging);

	sr := dx.SHADER_RESOURCE_VIEW_DESC {
		Format = desc.Format,
		ViewDimension = .TEXTURE2D,
		Texture2D = {
			MipLevels = 1,
		},
	};

	this.device->CreateShaderResourceView(texture, &sr, &view);

	out.id = auto_cast view;
	ok = true;
	return;
}

destroy_texture :: proc(texture: com.Texture) {
	if texture.id != nil {
		h := cast(^dx.IShaderResourceView)texture.id;
		h->Release();
	}
}
