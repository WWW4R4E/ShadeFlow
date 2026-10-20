const std = @import("std");

const win32 = @import("win32").everything;

const Error = @import("Error.zig");

pub const Device = struct {
    d3d_device: *win32.ID3D12Device,

    pub fn init() !Device {
        // 默认带调试层；系统没装「图形工具」可选功能时 D3D12CreateDevice 会
        // 直接失败（DXGI_ERROR_SDK_COMPONENT_MISSING），这时退回普通创建，
        // 而不是让整个引擎起不来。
        return create(true) catch |err| {
            std.log.warn("带调试层创建 D3D12 设备失败（{s}），回退到普通模式", .{@errorName(err)});
            return create(false);
        };
    }
    fn create(debug: bool) !Device {
        var d3d_device: ?*win32.ID3D12Device = null;

        // 1. 创建 DXGI 工厂
        var factory: win32.IDXGIFactory5 = undefined;
        // 注意：CreateDXGIFactory2 的 Flags 参数用于调试层，这里传 null 或 0
        const dvhr = win32.CreateDXGIFactory2(null, win32.IDD_IDXGIFactory2, @ptrCast(&factory));
        try Error.check(dvhr, "创建 DXGI 工厂");

        // 2. 枚举适配器，寻找第一个支持 D3D12 的硬件
        var adapter_index: u32 = 0;
        var adapter: ?*win32.IDXGIAdapter1 = null;
        var found = false;

        while (true) {
            const hr = factory.IDXGIFactory1.EnumAdapters1(adapter_index, &adapter);
            if (hr == win32.DXGI_ERROR_NOT_FOUND) break; // 没有更多适配器了
            try Error.check(hr, "枚举适配器");

            // 3. 尝试为当前适配器创建 D3D12 设备（仅测试，不真正创建）
            // 传入最小特性级别 11_0 和 ID3D12Device 的 GUID
            const test_hr = win32.D3D12CreateDevice(
                @ptrCast(adapter.?),
                win32.D3D_FEATURE_LEVEL_11_0,
                win32.IDD_ID3D12Device, // 或 &win32.IID_ID3D12Device
                null, // ppDevice 传 null 表示仅测试，不创建
            );

            if (test_hr == win32.S_OK or test_hr == win32.S_FALSE) {
                // 该适配器支持 D3D12，正式创建设备
                const create_hr = win32.D3D12CreateDevice(
                    @ptrCast(adapter.?),
                    win32.D3D_FEATURE_LEVEL_11_0,
                    win32.IDD_ID3D12Device,
                    @ptrCast(&d3d_device), // 输出参数，指向 *ID3D12Device 的指针
                );
                try Error.check(create_hr, "创建 D3D12 设备");
                found = true;
                break;
            }

            // 释放不支持的适配器
            _ = adapter.?.Release();
            adapter = null;
            adapter_index += 1;
        }

        if (!found) return error.NoCompatibleAdapter;

        // 如果 debug 为 true，可以在这里调用 D3D12GetDebugInterface 启用调试层
        // 注意：这需要在创建工厂或设备之前做，此处仅为示意

        return Device{
            .d3d_device = d3d_device.?,
        };
    }

    pub fn deinit(self: *Device) void {
        _ = self.d3d_device.IUnknown.Release();
    }

    pub fn getDevice(self: *Device) *win32.ID3D12Device {
        return self.d3d_device;
    }
};
