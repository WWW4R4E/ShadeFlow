//! DXGI 交换链。两种模式：
//! - Composition：交给 WinUI 3 的 `SwapChainPanel`（C# 侧 SetSwapChain）；
//! - HWND：独立窗口 demo。
//!
//! D3D12 的关键差异：`CreateSwapChainForHwnd/Composition` 的第一个参数是
//! **命令队列**（不是设备）。后台缓冲区状态在 PRESENT ↔ RENDER_TARGET 之间
//! 的切换屏障由 Renderer 录制。

const std = @import("std");

const win32 = @import("win32").everything;
const Error = @import("Error.zig");

const Device = @import("Device.zig").Device;
const buffer_count = @import("Device.zig").buffer_count;

pub const SwapChain = struct {
    handle: *win32.IDXGISwapChain1,
    width: u32,
    height: u32,

    pub fn initForComposition(device: *Device, width: u32, height: u32) !SwapChain {
        // WinUI Composition 要求 DXGI_SCALING_STRETCH；AlphaMode 用
        // PREMULTIPLIED 以支持与 UI 叠加。
        const desc = win32.DXGI_SWAP_CHAIN_DESC1{
            .Width = width,
            .Height = height,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = buffer_count,
            .Scaling = win32.DXGI_SCALING_STRETCH,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
            .AlphaMode = win32.DXGI_ALPHA_MODE_PREMULTIPLIED,
            .Flags = 0,
        };

        // target 传 null：稍后由 C# 端 ISwapChainPanelNative::SetSwapChain 绑定。
        var handle: *win32.IDXGISwapChain1 = undefined;
        const hr = device.factory.CreateSwapChainForComposition(
            @ptrCast(device.command_queue),
            &desc,
            null,
            @ptrCast(&handle),
        );
        try Error.check(hr, "创建 Composition 交换链");

        return SwapChain{ .handle = handle, .width = width, .height = height };
    }

    pub fn initForHwnd(device: *Device, hwnd: win32.HWND, width: u32, height: u32) !SwapChain {
        const desc = win32.DXGI_SWAP_CHAIN_DESC1{
            .Width = width,
            .Height = height,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = buffer_count,
            .Scaling = win32.DXGI_SCALING_NONE,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_DISCARD,
            .AlphaMode = win32.DXGI_ALPHA_MODE_UNSPECIFIED,
            .Flags = 0,
        };

        var handle: *win32.IDXGISwapChain1 = undefined;
        const hr = device.factory.CreateSwapChainForHwnd(
            @ptrCast(device.command_queue),
            hwnd,
            &desc,
            null,
            null,
            @ptrCast(&handle),
        );
        try Error.check(hr, "创建 HWND 交换链");

        return SwapChain{ .handle = handle, .width = width, .height = height };
    }

    pub fn present(self: *SwapChain) void {
        // 1 = 开启垂直同步。
        const base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        _ = base.Present(1, 0);
    }

    /// FLIP 模型下必须拿到当前后台缓冲区索引（D3D11 时代「只用 0 号」的写法不成立）。
    pub fn currentBackBufferIndex(self: *const SwapChain) u32 {
        const sc3: *win32.IDXGISwapChain3 = @ptrCast(self.handle);
        return sc3.GetCurrentBackBufferIndex();
    }

    /// 取第 index 个后台缓冲区（D3D12 侧是 ID3D12Resource）。
    pub fn getBackBuffer(self: *const SwapChain, index: u32) !*win32.ID3D12Resource {
        const base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        var resource: ?*win32.ID3D12Resource = null;
        try Error.check(
            base.GetBuffer(
                index,
                win32.IID_ID3D12Resource,
                @ptrCast(&resource),
            ),
            "获取后台缓冲区",
        );
        return resource.?;
    }

    /// 调整后台缓冲区大小。
    ///
    /// 调用前必须等 GPU 空闲并释放所有后台缓冲区引用与 RTV（Renderer 负责）。
    pub fn resizeBuffers(self: *SwapChain, width: u32, height: u32) !void {
        const base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        const hr = base.ResizeBuffers(
            0, // 保留原有 BufferCount
            width,
            height,
            win32.DXGI_FORMAT_UNKNOWN, // 保留原有格式
            0,
        );
        try Error.check(hr, "调整交换链大小");

        self.width = width;
        self.height = height;
    }

    pub fn deinit(self: *SwapChain) void {
        const base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        _ = base.IUnknown.Release();
    }
};
