const std = @import("std");

const win32 = @import("win32").everything;
const IID_IDXGIDevice = win32.IID_IDXGIDevice;
const IID_IDXGIAdapter = win32.IID_IDXGIAdapter;
const IID_IDXGIFactory2 = win32.IID_IDXGIFactory2;

const Device = @import("Device.zig").Device;

// com实现，需要undefined变量
var swap_chain: *win32.IDXGISwapChain1 = undefined;

// 引入必要的 GUID 和类型

pub const SwapChain = struct {
    // 统一只使用 IDXGISwapChain1
    handle: *win32.IDXGISwapChain1,
    width: u32,
    height: u32,

    // ---------------------------------------------------------
    // 模式 1: 为 WinUI 3 (Composition) 初始化
    // ---------------------------------------------------------
    pub fn initForComposition(device: *Device, width: u32, height: u32) !SwapChain {
        // 1. 获取 Factory (代码复用)
        const factory = try getFactoryFromDevice(device.d3d_device);
        defer _ = factory.IUnknown.Release();

        // 2. 配置描述符
        // 注意：WinUI Composition 必须使用 DXGI_SCALING_STRETCH
        // AlphaMode 通常设为 PREMULTIPLIED 以支持 UI 透明叠加，或者 IGNORE
        var desc = win32.DXGI_SWAP_CHAIN_DESC1{
            .Width = width,
            .Height = height,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2, // 现代 Flip 模型通常用 2
            .Scaling = win32.DXGI_SCALING_STRETCH, // 必须是 Stretch
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL, // 或 FLIP_DISCARD
            .AlphaMode = win32.DXGI_ALPHA_MODE_PREMULTIPLIED,
            .Flags = 0,
        };

        // 3. 创建 Composition SwapChain
        // 第三个参数 target 为 null，因为我们稍后会在 C# 端通过 SetSwapChain 绑定
        const hr = factory.CreateSwapChainForComposition(
            @ptrCast(device.d3d_device),
            &desc,
            null,
            &swap_chain,
        );

        if (hr != win32.S_OK) return error.FailedToCreateSwapChain;

        return SwapChain{
            .handle = swap_chain,
            .width = width,
            .height = height,
        };
    }

    // ---------------------------------------------------------
    // 模式 2: 为原生窗口 (HWND) 初始化 (调试用)
    // ---------------------------------------------------------
    pub fn initForHwnd(device: *Device, hwnd: win32.HWND, width: u32, height: u32) !SwapChain {
        const factory = try getFactoryFromDevice(device.d3d_device);
        defer _ = factory.IUnknown.Release();

        var desc = win32.DXGI_SWAP_CHAIN_DESC1{
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

        const hr = factory.CreateSwapChainForHwnd(
            @ptrCast(device.d3d_device),
            hwnd,
            &desc,
            null,
            null,
            @as(**win32.IDXGISwapChain1, @ptrCast(&swap_chain)),
        );

        if (hr != win32.S_OK) return error.FailedToCreateSwapChain;

        return SwapChain{
            .handle = swap_chain,
            .width = width,
            .height = height,
        };
    }

    // ---------------------------------------------------------
    // 通用方法
    // ---------------------------------------------------------

    pub fn present(self: *SwapChain) void {
        // 1 表示垂直同步开启，0 表示关闭
        // 现代 Flip 模型下，present 参数有所不同，但基本兼容
        const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        _ = swap_chain_base.Present(1, 0);
    }

    pub fn resizeBuffers(self: *SwapChain, width: u32, height: u32) !void {
        // 在 Resize 之前，必须释放所有指向 BackBuffer 的 RenderTargetView
        // 这一点非常重要，你需要确保外部调用者先调用 device.context.OMSetRenderTargets(0, null, null)

        // 转换为IDXGISwapChain基类指针再调用ResizeBuffers方法
        const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        const hr = swap_chain_base.ResizeBuffers(0, // 保留原有的 BufferCount
            width, height, win32.DXGI_FORMAT_UNKNOWN, // 保留原有格式
            0);

        if (hr != win32.S_OK) return error.FailedToResizeBuffers;

        self.width = width;
        self.height = height;
    }

    pub fn deinit(self: *SwapChain) void {
        const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(self.handle);
        _ = swap_chain_base.IUnknown.Release();
    }

    // ---------------------------------------------------------
    // 内部辅助：从 Device 获取 Factory
    // 这是一个极其稳健的方法，确保 Factory 和 Device 匹配
    // ---------------------------------------------------------
    // 内部辅助：从 Device 获取 Factory
    fn getFactoryFromDevice(d3d_device: *win32.ID3D11Device) !*win32.IDXGIFactory2 {
        // 1. Device -> DXGI Device
        var dxgi_device: ?*win32.IDXGIDevice = null;
        // QueryInterface 需要的是 ?*T，因为如果不匹配它会置空
        if (d3d_device.IUnknown.QueryInterface(win32.IID_IDXGIDevice, @ptrCast(&dxgi_device)) != win32.S_OK)
            return error.DxgiError;
        defer _ = dxgi_device.?.IUnknown.Release();

        // 2. DXGI Device -> Adapter
        // 【重要修改 1】这里使用 undefined 而不是 null，因为 GetAdapter 必返回非空指针
        var adapter: *win32.IDXGIAdapter = undefined;
        if (dxgi_device.?.GetAdapter(&adapter) != win32.S_OK)
            return error.DxgiError;
        defer _ = adapter.IUnknown.Release();

        // 3. Adapter -> Factory
        // 【重要修改 2】GetParent 是 IDXGIObject 的方法
        // 我们必须把 adapter 强转为 IDXGIObject 才能调用 GetParent
        const dxgi_object: *win32.IDXGIObject = @ptrCast(adapter);

        var factory: ?*win32.IDXGIFactory2 = null;
        // GetParent 的第二个参数是 void**
        if (dxgi_object.GetParent(win32.IID_IDXGIFactory2, @as(**anyopaque, @ptrCast(&factory))) != win32.S_OK)
            return error.DxgiError;

        return factory.?;
    }
};
