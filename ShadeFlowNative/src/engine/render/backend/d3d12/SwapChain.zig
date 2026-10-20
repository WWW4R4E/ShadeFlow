const std = @import("std");

const win32 = @import("win32").everything;
const Error = @import("Error.zig");

const Device = @import("Device.zig").Device;

/// DXGI 交换链，两种模式：
/// - Composition：交给 WinUI 3 的 `SwapChainPanel`（C# 侧 SetSwapChain）；
/// - HWND：独立窗口 demo。
///
/// 句柄由实例持有。以前这里是文件级全局变量，第二个 Renderer 会把它覆盖掉，
/// 多窗口/重建引擎时是隐性 UB。
pub const SwapChain = struct {
    handle: *win32.IDXGISwapChain1,
    width: u32,
    height: u32,

    pub fn initForComposition(device: *Device, width: u32, height: u32) !SwapChain {
        const factory = try getFactoryFromDevice(device.d3d_device);
        defer _ = factory.IUnknown.Release();

        // WinUI Composition 要求 DXGI_SCALING_STRETCH；AlphaMode 用
        // PREMULTIPLIED 以支持与 UI 叠加。
        const desc = win32.DXGI_SWAP_CHAIN_DESC1{
            .Width = width,
            .Height = height,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .Scaling = win32.DXGI_SCALING_STRETCH,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
            .AlphaMode = win32.DXGI_ALPHA_MODE_PREMULTIPLIED,
            .Flags = 0,
        };

        // target 传 null：稍后由 C# 端 ISwapChainPanelNative::SetSwapChain 绑定。
        var handle: *win32.IDXGISwapChain1 = undefined;
        const hr = factory.CreateSwapChainForComposition(
            @ptrCast(device.d3d_device),
            &desc,
            null,
            @ptrCast(&handle),
        );
        try Error.check(hr, "创建 Composition 交换链");

        return SwapChain{ .handle = handle, .width = width, .height = height };
    }

    pub fn initForHwnd(device: *Device, hwnd: win32.HWND, width: u32, height: u32) !SwapChain {
        const factory = try getFactoryFromDevice(device.d3d_device);
        defer _ = factory.IUnknown.Release();

        const desc = win32.DXGI_SWAP_CHAIN_DESC1{
            .Width = width,
            .Height = height,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .Scaling = win32.DXGI_SCALING_NONE,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_DISCARD,
            .AlphaMode = win32.DXGI_ALPHA_MODE_UNSPECIFIED,
            .Flags = 0,
        };

        var handle: *win32.IDXGISwapChain1 = undefined;
        const hr = factory.CreateSwapChainForHwnd(
            @ptrCast(device.d3d_device),
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

    /// 调整后台缓冲区大小。
    ///
    /// 调用前必须释放所有指向 BackBuffer 的视图（RTV），并解绑渲染目标。
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

    /// 从 Device 取与之匹配的 Factory。
    fn getFactoryFromDevice(d3d_device: *win32.ID3D12Device) !*win32.IDXGIFactory2 {
        var dxgi_device: ?*win32.IDXGIDevice = null;
        try Error.check(
            d3d_device.IUnknown.QueryInterface(win32.IID_IDXGIDevice, @ptrCast(&dxgi_device)),
            "获取 IDXGIDevice",
        );
        defer _ = dxgi_device.?.IUnknown.Release();

        var adapter: *win32.IDXGIAdapter = undefined;
        try Error.check(dxgi_device.?.GetAdapter(&adapter), "获取 IDXGIAdapter");
        defer _ = adapter.IUnknown.Release();

        const dxgi_object: *win32.IDXGIObject = @ptrCast(adapter);
        var factory: ?*win32.IDXGIFactory2 = null;
        try Error.check(
            dxgi_object.GetParent(win32.IID_IDXGIFactory2, @as(**anyopaque, @ptrCast(&factory))),
            "获取 IDXGIFactory2",
        );

        return factory.?;
    }
};
