const std = @import("std");

const win32 = @import("win32").everything;

const Types = @import("render_types");
const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

/// 缓冲区类型。与 `Types.BufferUsage` 不同：这里描述「用途/绑定槽」，
/// 后者描述「CPU/GPU 可见性」。
pub const BufferType = enum {
    vertex,
    index,
    constant,
};

pub const Buffer = struct {
    buffer: ?*win32.ID3D11Buffer = null,
    buffer_type: BufferType,
    stride: u32 = 0,
    count: u32 = 0,

    pub fn init(buffer_type: BufferType) Buffer {
        return .{ .buffer_type = buffer_type };
    }

    pub fn createVertexBuffer(
        self: *Buffer,
        device: *Device,
        data: []const u8,
        stride: u32,
        usage: Types.BufferUsage,
    ) !void {
        if (self.buffer_type != .vertex) return error.InvalidBufferType;
        if (stride == 0) return error.InvalidStride;

        var buffer_usage: win32.D3D11_USAGE = undefined;
        var cpu_access_flags: win32.D3D11_CPU_ACCESS_FLAG = @bitCast(@as(u32, 0));

        switch (usage) {
            .default => buffer_usage = win32.D3D11_USAGE_DEFAULT,
            .dynamic => {
                buffer_usage = win32.D3D11_USAGE_DYNAMIC;
                cpu_access_flags = win32.D3D11_CPU_ACCESS_WRITE;
            },
            .immutable => buffer_usage = win32.D3D11_USAGE_IMMUTABLE,
        }

        const desc = win32.D3D11_BUFFER_DESC{
            .ByteWidth = @intCast(data.len),
            .Usage = buffer_usage,
            .BindFlags = win32.D3D11_BIND_VERTEX_BUFFER,
            .CPUAccessFlags = cpu_access_flags,
            .MiscFlags = @bitCast(@as(u32, 0)),
            .StructureByteStride = 0,
        };

        // 动态缓冲区不能带初始数据。
        var initial_data: ?win32.D3D11_SUBRESOURCE_DATA = null;
        if (usage != .dynamic) {
            initial_data = .{ .pSysMem = data.ptr, .SysMemPitch = 0, .SysMemSlicePitch = 0 };
        }

        var handle: ?*win32.ID3D11Buffer = null;
        try Error.check(
            device.d3d_device.CreateBuffer(&desc, if (initial_data) |*d| d else null, @ptrCast(&handle)),
            "创建顶点缓冲区",
        );

        self.replace(handle.?);
        self.stride = stride;
        self.count = @intCast(data.len / stride);
    }

    pub fn createIndexBuffer(self: *Buffer, device: *Device, data: []const u32) !void {
        if (self.buffer_type != .index) return error.InvalidBufferType;

        const desc = win32.D3D11_BUFFER_DESC{
            .ByteWidth = @intCast(data.len * @sizeOf(u32)),
            .Usage = win32.D3D11_USAGE_DEFAULT,
            .BindFlags = win32.D3D11_BIND_INDEX_BUFFER,
            .CPUAccessFlags = .{},
            .MiscFlags = @bitCast(@as(u32, 0)),
            .StructureByteStride = 0,
        };
        const initial_data = win32.D3D11_SUBRESOURCE_DATA{
            .pSysMem = data.ptr,
            .SysMemPitch = 0,
            .SysMemSlicePitch = 0,
        };

        var handle: ?*win32.ID3D11Buffer = null;
        try Error.check(
            device.d3d_device.CreateBuffer(&desc, &initial_data, @ptrCast(&handle)),
            "创建索引缓冲区",
        );

        self.replace(handle.?);
        self.stride = @sizeOf(u32);
        self.count = @intCast(data.len);
    }

    pub fn createConstantBuffer(self: *Buffer, device: *Device, size: u32) !void {
        if (self.buffer_type != .constant) return error.InvalidBufferType;

        const desc = win32.D3D11_BUFFER_DESC{
            .ByteWidth = size,
            .Usage = win32.D3D11_USAGE_DYNAMIC,
            .BindFlags = win32.D3D11_BIND_CONSTANT_BUFFER,
            .CPUAccessFlags = win32.D3D11_CPU_ACCESS_WRITE,
            .MiscFlags = @bitCast(@as(u32, 0)),
            .StructureByteStride = 0,
        };

        var handle: ?*win32.ID3D11Buffer = null;
        try Error.check(
            device.d3d_device.CreateBuffer(&desc, null, @ptrCast(&handle)),
            "创建常量缓冲区",
        );

        self.replace(handle.?);
        self.stride = 0;
        self.count = 0;
    }

    pub fn updateConstantBuffer(
        self: *Buffer,
        device_context: *win32.ID3D11DeviceContext,
        data: []const u8,
    ) !void {
        if (self.buffer_type != .constant) return error.InvalidBufferType;
        if (self.buffer == null) return error.BufferNotCreated;

        var mapped: win32.D3D11_MAPPED_SUBRESOURCE = undefined;
        try Error.check(
            device_context.Map(@ptrCast(self.buffer.?), 0, win32.D3D11_MAP_WRITE_DISCARD, 0, &mapped),
            "映射常量缓冲区",
        );
        defer device_context.Unmap(@ptrCast(self.buffer.?), 0);

        const dst: [*]u8 = @ptrCast(mapped.pData.?);
        @memcpy(dst[0..data.len], data);
    }

    pub fn bindVertexBuffer(self: *const Buffer, device_context: *win32.ID3D11DeviceContext, slot: u32) void {
        if (self.buffer_type != .vertex) return;
        const handle = self.buffer orelse return;

        var buffers = [_]?*win32.ID3D11Buffer{handle};
        var strides = [_]u32{self.stride};
        var offsets = [_]u32{0};
        device_context.IASetVertexBuffers(slot, 1, @ptrCast(&buffers[0]), @ptrCast(&strides[0]), @ptrCast(&offsets[0]));
    }

    pub fn bindIndexBuffer(self: *const Buffer, device_context: *win32.ID3D11DeviceContext) void {
        if (self.buffer_type != .index) return;
        const handle = self.buffer orelse return;

        device_context.IASetIndexBuffer(handle, win32.DXGI_FORMAT_R32_UINT, 0);
    }

    pub fn bindConstantBufferVS(self: *const Buffer, device_context: *win32.ID3D11DeviceContext, slot: u32) void {
        if (self.buffer_type != .constant) return;
        const handle = self.buffer orelse return;

        var buffers = [_]?*win32.ID3D11Buffer{handle};
        device_context.VSSetConstantBuffers(slot, 1, @ptrCast(&buffers[0]));
    }

    pub fn bindConstantBufferPS(self: *const Buffer, device_context: *win32.ID3D11DeviceContext, slot: u32) void {
        if (self.buffer_type != .constant) return;
        const handle = self.buffer orelse return;

        var buffers = [_]?*win32.ID3D11Buffer{handle};
        device_context.PSSetConstantBuffers(slot, 1, @ptrCast(&buffers[0]));
    }

    pub fn deinit(self: *Buffer) void {
        if (self.buffer) |handle| _ = handle.IUnknown.Release();
        self.buffer = null;
    }

    fn replace(self: *Buffer, handle: *win32.ID3D11Buffer) void {
        if (self.buffer) |old| _ = old.IUnknown.Release();
        self.buffer = handle;
    }
};
