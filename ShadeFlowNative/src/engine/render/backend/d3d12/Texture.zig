//! D3D12 纹理。当前引擎只用深度缓冲（后台缓冲区由 SwapChain/Renderer 管理），
//! 纹理资源（着色器资源 / 渲染目标）等资源导入落地后再补。

const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const Error = @import("Error.zig");

pub const TextureType = enum { depth_stencil };

pub const Texture = struct {
    texture_type: TextureType,
    resource: ?*win32.ID3D12Resource = null,
    /// 深度缓冲自带的 1 槽 DSV 堆（非 shader-visible）。
    dsv_heap: ?*win32.ID3D12DescriptorHeap = null,

    pub fn init(texture_type: TextureType) Texture {
        return .{ .texture_type = texture_type };
    }

    pub fn createDepthStencil(self: *Texture, device: *Device, width: u32, height: u32) !void {
        std.debug.assert(self.texture_type == .depth_stencil);
        std.debug.assert(self.resource == null);

        const heap_props = win32.D3D12_HEAP_PROPERTIES{
            .Type = .DEFAULT,
            .CPUPageProperty = .UNKNOWN,
            .MemoryPoolPreference = .UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };
        const desc = win32.D3D12_RESOURCE_DESC{
            .Dimension = .TEXTURE2D,
            .Alignment = 0,
            .Width = width,
            .Height = height,
            .DepthOrArraySize = 1,
            .MipLevels = 1,
            .Format = win32.DXGI_FORMAT_D32_FLOAT,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = .UNKNOWN,
            .Flags = .{ .ALLOW_DEPTH_STENCIL = 1 },
        };
        const clear_value = win32.D3D12_CLEAR_VALUE{
            .Format = win32.DXGI_FORMAT_D32_FLOAT,
            .Anonymous = .{ .DepthStencil = .{ .Depth = 1.0, .Stencil = 0 } },
        };

        var resource: ?*win32.ID3D12Resource = null;
        try Error.check(
            device.d3d_device.CreateCommittedResource(
                &heap_props,
                win32.D3D12_HEAP_FLAG_NONE,
                &desc,
                win32.D3D12_RESOURCE_STATE_DEPTH_WRITE,
                &clear_value,
                win32.IID_ID3D12Resource,
                @ptrCast(&resource),
            ),
            "创建深度缓冲",
        );
        errdefer _ = resource.?.IUnknown.Release();

        const heap_desc = win32.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = .DSV,
            .NumDescriptors = 1,
            .Flags = win32.D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            .NodeMask = 0,
        };
        var dsv_heap: ?*win32.ID3D12DescriptorHeap = null;
        try Error.check(
            device.d3d_device.CreateDescriptorHeap(&heap_desc, win32.IID_ID3D12DescriptorHeap, @ptrCast(&dsv_heap)),
            "创建 DSV 堆",
        );
        errdefer _ = dsv_heap.?.IUnknown.Release();

        device.d3d_device.CreateDepthStencilView(resource.?, null, dsv_heap.?.GetCPUDescriptorHandleForHeapStart());

        self.resource = resource;
        self.dsv_heap = dsv_heap;
    }

    pub fn getDepthStencilView(self: *const Texture) ?win32.D3D12_CPU_DESCRIPTOR_HANDLE {
        if (self.dsv_heap) |heap| return heap.GetCPUDescriptorHandleForHeapStart();
        return null;
    }

    pub fn deinit(self: *Texture) void {
        if (self.dsv_heap) |heap| _ = heap.IUnknown.Release();
        if (self.resource) |res| _ = res.IUnknown.Release();
        self.dsv_heap = null;
        self.resource = null;
    }
};
