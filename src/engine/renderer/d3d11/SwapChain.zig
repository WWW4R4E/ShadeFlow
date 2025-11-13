const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;

pub const SwapChain = struct {
    swap_chain: *win32.IDXGISwapChain,
    render_target_view: *win32.ID3D11RenderTargetView,
    back_buffer: *win32.ID3D11Texture2D,
    width: u32,
    height: u32,

    pub fn init(device: *Device, hwnd: win32.HWND, width: u32, height: u32) !SwapChain {
        var swap_chain: ?*win32.IDXGISwapChain = null;

        var swap_chain_desc = win32.DXGI_SWAP_CHAIN_DESC{
            .BufferDesc = .{
                .Width = width,
                .Height = height,
                .RefreshRate = .{
                    .Numerator = 60,
                    .Denominator = 1,
                },
                .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
                .ScanlineOrdering = win32.DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED,
                .Scaling = win32.DXGI_MODE_SCALING_UNSPECIFIED,
            },
            .SampleDesc = .{
                .Count = 1,
                .Quality = 0,
            },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .OutputWindow = hwnd,
            .Windowed = 1,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_DISCARD,
            .Flags = 0,
        };

        var dxgi_factory: ?*win32.IDXGIFactory = null;
        const hr_factory = win32.CreateDXGIFactory(win32.IID_IDXGIFactory, @as(**anyopaque, @ptrCast(&dxgi_factory)));
        if (hr_factory != win32.S_OK) {
            return error.FailedToCreateDXGIFactory;
        }
        defer _ = dxgi_factory.?.IUnknown.Release();

        const hr = dxgi_factory.?.CreateSwapChain(
            @ptrCast(device.d3d_device),
            &swap_chain_desc,
            @ptrCast(&swap_chain),
        );

        if (hr != win32.S_OK) {
            return error.FailedToCreateSwapChain;
        }

        // 获取后缓冲并创建渲染目标视图
        var back_buffer: ?*win32.ID3D11Texture2D = null;
        if (swap_chain.?.GetBuffer(0, win32.IID_ID3D11Texture2D, @as(**anyopaque, @ptrCast(&back_buffer))) != win32.S_OK) {
            return error.FailedToGetBackBuffer;
        }

        var render_target_view: *win32.ID3D11RenderTargetView = undefined;

        if (device.d3d_device.CreateRenderTargetView(@as(*win32.ID3D11Resource, @ptrCast(back_buffer.?)), null,  &render_target_view) != win32.S_OK) {
            return error.FailedToCreateRenderTargetView;
        }

        return SwapChain{
            .swap_chain = swap_chain.?,
            .render_target_view = render_target_view,
            .back_buffer = back_buffer.?,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *SwapChain) void {
        _ = self.render_target_view.IUnknown.Release();
        _ = self.back_buffer.IUnknown.Release();
        _ = self.swap_chain.IUnknown.Release();
    }

    pub fn present(self: *SwapChain) void {
        _ = self.swap_chain.Present(1, 0); 
    }

    pub fn clear(self: *SwapChain, device_context: *win32.ID3D11DeviceContext, color: [4]f32) void {
        device_context.ClearRenderTargetView(self.render_target_view, @ptrCast(&color));
    }

    pub fn getRenderTargetView(self: *SwapChain) *win32.ID3D11RenderTargetView {
        return self.render_target_view;
    }
};
