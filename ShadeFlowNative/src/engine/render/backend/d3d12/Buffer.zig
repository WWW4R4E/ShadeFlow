//! D3D12 缓冲区：顶点 / 索引 / 常量。
//!
//! 全部放在 UPLOAD 堆（GENERIC_READ 初始状态），创建时一次性 memcpy：
//! 顶点/索引是低频静态数据，常量每帧覆写。上传堆常驻映射（Map 一次不 Unmap），
//! 省掉每帧 Map/Unmap 的开销；不需要 default 堆 + 拷贝队列那条更复杂的路径。

const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

pub const BufferType = enum { vertex, index, constant, upload };

/// D3D12 要求常量缓冲的 GPU 地址按 256 字节对齐（绑定偏移也按这个粒度）。
pub const constant_buffer_alignment = 256;

pub const Buffer = struct {
    buffer_type: BufferType,
    resource: ?*win32.ID3D12Resource = null,
    /// 上传堆的常驻 CPU 映射；顶点/索引缓冲创建完拷贝后即可 Unmap，这里是 null。
    mapped_ptr: ?[*]u8 = null,
    size: u32 = 0,
    stride: u32 = 0,
    /// 顶点数（顶点缓冲）或索引数（索引缓冲），引擎的 scene 层会读它。
    count: u32 = 0,

    pub fn init(buffer_type: BufferType) Buffer {
        return .{ .buffer_type = buffer_type };
    }

    /// 顶点缓冲：`stride` 是单顶点字节数。静态只读——上传堆一次性写入。
    pub fn createVertexBuffer(
        self: *Buffer,
        device: *Device,
        data: []const u8,
        stride: u32,
    ) !void {
        try self.createUpload(device, @intCast(data.len));
        @memcpy(self.mapped_ptr.?[0..data.len], data);
        self.stride = stride;
        self.count = if (stride != 0) @intCast(data.len / stride) else 0;
        self.unmapIfStatic();
    }

    pub fn createIndexBuffer(self: *Buffer, device: *Device, indices: []const u32) !void {
        const bytes = std.mem.sliceAsBytes(indices);
        try self.createUpload(device, @intCast(bytes.len));
        @memcpy(self.mapped_ptr.?[0..bytes.len], bytes);
        self.count = @intCast(indices.len);
        self.unmapIfStatic();
    }

    /// 常量缓冲：`size` 必须已按 256 对齐（调用方负责，见 Renderer 的常量槽位）。
    pub fn createConstantBuffer(self: *Buffer, device: *Device, size: u32) !void {
        try self.createUpload(device, size);
        // 常量缓冲保持映射：每帧 updateConstantBuffer 直接写。
    }

    /// 纹理上传用的中转缓冲：UPLOAD 堆 + 保持映射，调用方 memcpy 后提交拷贝。
    pub fn createForUpload(self: *Buffer, device: *Device, size: u32) !void {
        try self.createUpload(device, size);
        // createUpload 不主动 Unmap（那是静态数据拷贝后的收尾步骤），这里保持映射
        // 直到 deinit——upload 缓冲生命周期只覆盖一次提交。
    }

    pub fn updateConstantBuffer(self: *Buffer, data: []const u8, offset: u32) void {
        const ptr = self.mapped_ptr orelse return;
        const end = @min(@as(usize, offset) + data.len, self.size);
        if (offset >= end) return;
        @memcpy(ptr[offset..end], data[0 .. end - offset]);
    }

    pub fn gpuVirtualAddress(self: *const Buffer) u64 {
        return self.resource.?.GetGPUVirtualAddress();
    }

    pub fn deinit(self: *Buffer) void {
        if (self.resource) |res| {
            if (self.mapped_ptr != null) res.Unmap(0, null);
            _ = res.IUnknown.Release();
        }
        self.resource = null;
        self.mapped_ptr = null;
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn createUpload(self: *Buffer, device: *Device, size: u32) !void {
        std.debug.assert(self.resource == null);
        if (size == 0) return error.EmptyBuffer;

        const heap_props = win32.D3D12_HEAP_PROPERTIES{
            .Type = .UPLOAD,
            .CPUPageProperty = .UNKNOWN,
            .MemoryPoolPreference = .UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };
        const desc = win32.D3D12_RESOURCE_DESC{
            .Dimension = .BUFFER,
            .Alignment = 0,
            .Width = size,
            .Height = 1,
            .DepthOrArraySize = 1,
            // buffer 资源的 MipLevels 必须是 1（写 0 报 CREATERESOURCE_INVALIDMIPLEVELS / E_INVALIDARG）
            .MipLevels = 1,
            .Format = .UNKNOWN,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = .ROW_MAJOR,
            .Flags = win32.D3D12_RESOURCE_FLAG_NONE,
        };

        var resource: ?*win32.ID3D12Resource = null;
        try Error.check(
            device.d3d_device.CreateCommittedResource(
                &heap_props,
                win32.D3D12_HEAP_FLAG_NONE,
                &desc,
                win32.D3D12_RESOURCE_STATE_GENERIC_READ,
                null,
                win32.IID_ID3D12Resource,
                @ptrCast(&resource),
            ),
            "创建上传堆缓冲区",
        );

        var mapped: ?*anyopaque = null;
        try Error.check(resource.?.Map(0, null, &mapped), "映射上传堆缓冲区");

        self.resource = resource;
        self.mapped_ptr = @ptrCast(@alignCast(mapped));
        self.size = size;
    }

    /// 静态数据拷完就没必要保持映射（也省得 deinit 再判空）。
    fn unmapIfStatic(self: *Buffer) void {
        if (self.buffer_type != .constant) {
            self.resource.?.Unmap(0, null);
            self.mapped_ptr = null;
        }
    }
};
