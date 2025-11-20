const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const HResultError = @import("Error.zig").HResultError;

// 缓冲区类型枚举
pub const BufferType = enum {
    vertex,
    index,
    constant,
};

pub const Buffer = struct {
    buffer: ?*win32.ID3D11Buffer,
    buffer_type: BufferType,
    stride: u32,
    count: u32,

    pub fn init(buffer_type: BufferType) Buffer {
        return Buffer{
            .buffer = null,
            .buffer_type = buffer_type,
            .stride = 0,
            .count = 0,
        };
    }

    pub fn createVertexBuffer(self: *Buffer, device: *Device, data: []const u8, stride: u32, usage: enum { default, dynamic, immutable }) !void {
        // 确保是顶点缓冲区类型
        if (self.buffer_type != .vertex) {
            return error.InvalidBufferType;
        }

        // 计算使用标志
        var buffer_usage: win32.D3D11_USAGE = undefined;
        var cpu_access_flags: win32.D3D11_CPU_ACCESS_FLAG = @bitCast(@as(u32, 0));

        switch (usage) {
            .default => {
                buffer_usage = win32.D3D11_USAGE_DEFAULT;
            },
            .dynamic => {
                buffer_usage = win32.D3D11_USAGE_DYNAMIC;
                cpu_access_flags = win32.D3D11_CPU_ACCESS_WRITE;
            },
            .immutable => {
                buffer_usage = win32.D3D11_USAGE_IMMUTABLE;
                cpu_access_flags = @bitCast(@as(u32, 0));
            },
        }

        // 创建缓冲区描述
        const buffer_desc = win32.D3D11_BUFFER_DESC{
            .ByteWidth = @intCast(data.len),
            .Usage = buffer_usage,
            .BindFlags = win32.D3D11_BIND_VERTEX_BUFFER,
            .CPUAccessFlags = cpu_access_flags,
            .MiscFlags = @bitCast(@as(u32, 0)),
            .StructureByteStride = 0, // 顶点缓冲区通常设置为0
        };

        // 设置初始数据
        var initial_data: ?win32.D3D11_SUBRESOURCE_DATA = null;
        if (usage != .dynamic) {
            initial_data = .{
                .pSysMem = data.ptr,
                .SysMemPitch = 0,
                .SysMemSlicePitch = 0,
            };
        }

        // 创建缓冲区
        var buffer: ?*win32.ID3D11Buffer = null;
        const hr = device.d3d_device.CreateBuffer(&buffer_desc, if (initial_data) |*id| id else null, @ptrCast(&buffer));
        if (hr != win32.S_OK) {
            var hresult_error: HResultError = undefined;
            hresult_error.init(hr);
            return error.HResultError;
        }

        // 释放旧缓冲区
        if (self.buffer) |b| _ = b.IUnknown.Release();

        // 更新状态
        self.buffer = buffer;
        self.stride = stride;
        self.count = @intCast(data.len / stride);
    }

    pub fn createIndexBuffer(self: *Buffer, device: *Device, data: []const u16) !void {
        // 确保是索引缓冲区类型
        if (self.buffer_type != .index) {
            std.debug.print("Invalid buffer type\n", .{});
            return error.InvalidBufferType;
        }

        // 创建缓冲区描述
        const buffer_desc = win32.D3D11_BUFFER_DESC{
            .ByteWidth = @intCast(data.len * @sizeOf(u16)),
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_INDEX_BUFFER,
            .CPUAccessFlags = .{},
            .MiscFlags = @bitCast(@as(u32, 0)),
            .StructureByteStride = 0,
        };

        // 设置初始数据
        const initial_data = win32.D3D11_SUBRESOURCE_DATA{
            .pSysMem = data.ptr,
            .SysMemPitch = 0,
            .SysMemSlicePitch = 0,
        };

        // 创建缓冲区
        var buffer: ?*win32.ID3D11Buffer = null;
        const hr = device.d3d_device.CreateBuffer(&buffer_desc, &initial_data, @ptrCast(&buffer));
        if (hr != win32.S_OK) {
            var hresult_error: HResultError = undefined;
            hresult_error.init(hr);
            return error.HResultError;
        }

        // 释放旧缓冲区
        if (self.buffer) |b| _ = b.IUnknown.Release();

        // 更新状态
        self.buffer = buffer;
        self.stride = @sizeOf(u16);
        self.count = @intCast(data.len);
    }

    pub fn createConstantBuffer(self: *Buffer, device: *Device, size: u32) HResultError!void {
        // 确保是常量缓冲区类型
        if (self.buffer_type != .constant) {
            return error.InvalidBufferType;
        }

        // 创建缓冲区描述
        const buffer_desc = win32.D3D11_BUFFER_DESC{
            .ByteWidth = size,
            .Usage = win32.D3D11_USAGE_DYNAMIC,
            .BindFlags = win32.D3D11_BIND_CONSTANT_BUFFER,
            .CPUAccessFlags = win32.D3D11_CPU_ACCESS_WRITE,
            .MiscFlags = @bitCast(@as(u32, 0)),
            .StructureByteStride = 0,
        };

        // 创建缓冲区
        var buffer: ?*win32.ID3D11Buffer = null;
        const hr = device.d3d_device.CreateBuffer(&buffer_desc, null, &buffer);
        if (hr != win32.S_OK) {
            std.debug.print("Failed to create constant buffer: 0x{X}\n", .{hr});
            return HResultError.init(hr);
        }

        // 释放旧缓冲区
        if (self.buffer) |b| _ = b.IUnknown.Release();

        // 更新状态
        self.buffer = buffer;
        self.stride = 0;
        self.count = 0;
    }

    pub fn updateConstantBuffer(self: *Buffer, device_context: *win32.ID3D11DeviceContext, data: []const u8) HResultError!void {
        if (self.buffer_type != .constant) {
            return error.InvalidBufferType;
        }

        if (self.buffer == null) {
            return error.BufferNotCreated;
        }

        // 映射缓冲区
        var mapped_resource: win32.D3D11_MAPPED_SUBRESOURCE = undefined;
        const hr = device_context.Map(self.buffer.?, 0, win32.D3D11_MAP_WRITE_DISCARD, 0, &mapped_resource);
        if (hr != win32.S_OK) {
            return HResultError.init(hr);
        }

        // 复制数据
        @memcpy(mapped_resource.pData[0..data.len], data.ptr);

        // 取消映射
        device_context.Unmap(self.buffer.?, 0);
    }

    pub fn bindVertexBuffer(self: *const Buffer, device_context: *win32.ID3D11DeviceContext, slot: u32) void {
        if (self.buffer_type == .vertex and self.buffer != null) {
            var buffer_array = [_]?*win32.ID3D11Buffer{self.buffer};
            var stride_array = [_]u32{self.stride};
            var offset_array = [_]u32{0};

            device_context.IASetVertexBuffers(slot, 1, @ptrCast(&buffer_array[0]), @ptrCast(&stride_array[0]), @ptrCast(&offset_array[0]));
        }
    }

    pub fn bindIndexBuffer(self: *const Buffer, device_context: *win32.ID3D11DeviceContext) void {
        if (self.buffer_type == .index and self.buffer != null) {
            device_context.IASetIndexBuffer(self.buffer.?, win32.DXGI_FORMAT_R16_UINT, 0);
        }
    }

    pub fn bindConstantBufferVS(self: *const Buffer, device_context: *win32.ID3D11DeviceContext, slot: u32) void {
        if (self.buffer_type == .constant and self.buffer != null) {
            device_context.VSSetConstantBuffers(slot, 1, &self.buffer);
        }
    }

    pub fn bindConstantBufferPS(self: *Buffer, device_context: *win32.ID3D11DeviceContext, slot: u32) void {
        if (self.buffer_type == .constant and self.buffer != null) {
            device_context.PSSetConstantBuffers(slot, 1, &self.buffer);
        }
    }

    pub fn deinit(self: *Buffer) void {
        if (self.buffer) |b| _ = b.IUnknown.Release();
        self.buffer = null;
    }
};
