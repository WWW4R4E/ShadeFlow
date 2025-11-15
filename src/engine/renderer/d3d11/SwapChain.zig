const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const HResultError = @import("Error.zig").HResultError;

pub const SwapChain = struct {
    swap_chain: *win32.IDXGISwapChain,
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
            .BufferCount = 1, 
            .OutputWindow = hwnd,
            .Windowed = 1,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_DISCARD,
            .Flags = 0,
        };

        var dxgi_factory: ?*win32.IDXGIFactory = null;
        const hr_factory = win32.CreateDXGIFactory(win32.IID_IDXGIFactory, @as(**anyopaque, @ptrCast(&dxgi_factory)));
        if (hr_factory != win32.S_OK) {
            var hr_error: HResultError = undefined;
            hr_error.init(hr_factory);
            return error.HResultError;
        }
        defer _ = dxgi_factory.?.IUnknown.Release();

        const hr = dxgi_factory.?.CreateSwapChain(
            @ptrCast(@alignCast(device.d3d_device)),
            &swap_chain_desc,
            @ptrCast(@alignCast(&swap_chain)),
        );

        if (hr != win32.S_OK) {
            var hr_error: HResultError = undefined;
            hr_error.init(hr);
            return error.HResultError;
        }

        return SwapChain{
            .swap_chain = swap_chain.?,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *SwapChain) void {
        _ = self.swap_chain.IUnknown.Release();
    }

    pub fn present(self: *SwapChain) void {
        _ = self.swap_chain.Present(1, 0);
    }

    // 调整交换链缓冲区大小
    pub fn resizeBuffers(self: *SwapChain, width: u32, height: u32) !void {
        const hr = self.swap_chain.ResizeBuffers(
            0, // 保留缓冲区数量
            width,
            height,
            win32.DXGI_FORMAT_UNKNOWN, // 保留当前格式
            0  // 无特殊标志
        );

        if (hr != win32.S_OK) {
            return error.FailedToResizeBuffers;
        }

        self.width = width;
        self.height = height;
    }
};
