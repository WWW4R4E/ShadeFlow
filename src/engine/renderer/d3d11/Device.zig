const std = @import("std");

const win32 = @import("win32").everything;

pub const Device = struct {
    d3d_device: *win32.ID3D11Device,
    device_context: *win32.ID3D11DeviceContext,

    pub fn init() !Device {
        var d3d_device: ?*win32.ID3D11Device = null;
        var device_context: ?*win32.ID3D11DeviceContext = null;

        const creation_flags = win32.D3D11_CREATE_DEVICE_DEBUG;
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

        if (hr != win32.S_OK) {
            return error.FailedToCreateD3DDevice;
        }

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