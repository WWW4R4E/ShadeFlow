const std = @import("std");

const win32 = @import("win32").everything;

const Error = @import("Error.zig");

pub const Device = struct {
    d3d_device: *win32.ID3D11Device,
    device_context: *win32.ID3D11DeviceContext,

    pub fn init() !Device {
        // 默认带调试层；系统没装「图形工具」可选功能时 D3D11CreateDevice 会
        // 直接失败（DXGI_ERROR_SDK_COMPONENT_MISSING），这时退回普通创建，
        // 而不是让整个引擎起不来。
        return create(true) catch |err| {
            std.log.warn("带调试层创建 D3D11 设备失败（{s}），回退到普通模式", .{@errorName(err)});
            return create(false);
        };
    }

    fn create(debug: bool) !Device {
        var d3d_device: ?*win32.ID3D11Device = null;
        var device_context: ?*win32.ID3D11DeviceContext = null;

        const creation_flags: win32.D3D11_CREATE_DEVICE_FLAG = if (debug)
            win32.D3D11_CREATE_DEVICE_DEBUG
        else
            @bitCast(@as(u32, 0));

        const feature_levels = [_]win32.D3D_FEATURE_LEVEL{
            win32.D3D_FEATURE_LEVEL_11_0,
            win32.D3D_FEATURE_LEVEL_10_1,
            win32.D3D_FEATURE_LEVEL_10_0,
        };
        var actual_feature_level: win32.D3D_FEATURE_LEVEL = undefined;

        const hr = win32.D3D11CreateDevice(
            null, // 显卡适配器
            win32.D3D_DRIVER_TYPE_HARDWARE,
            null,
            creation_flags,
            &feature_levels,
            feature_levels.len,
            win32.D3D11_SDK_VERSION,
            @ptrCast(&d3d_device),
            &actual_feature_level,
            @ptrCast(&device_context),
        );
        try Error.check(hr, "创建 D3D11 设备");

        return Device{
            .d3d_device = d3d_device.?,
            .device_context = device_context.?,
        };
    }

    pub fn deinit(self: *Device) void {
        _ = self.device_context.IUnknown.Release();
        _ = self.d3d_device.IUnknown.Release();
    }

    pub fn getDevice(self: *Device) *win32.ID3D11Device {
        return self.d3d_device;
    }

    pub fn getDeviceContext(self: *Device) *win32.ID3D11DeviceContext {
        return self.device_context;
    }
};
