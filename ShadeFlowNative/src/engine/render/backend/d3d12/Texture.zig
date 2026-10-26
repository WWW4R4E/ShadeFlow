//! D3D12 纹理。
//!
//! - `depth_stencil`：深度缓冲（由 Renderer 的管线资源管理，自带 1 槽 DSV 堆）。
//! - `color_2d`：RGBA8 颜色纹理——default 堆 + upload 堆 + CopyTextureRegion
//!   一次性上传（fence 等待，加载期低频可接受），SRV/采样器写进 Device 的
//!   shader-visible 堆静态槽位，创建后绘制期零额外开销。

const std = @import("std");

const win32 = @import("win32").everything;

const Device = @import("Device.zig").Device;
const DeviceSlots = @import("Device.zig");
const Error = @import("Error.zig");

pub const TextureType = enum { color_2d, depth_stencil };

pub const Texture = struct {
    texture_type: TextureType,
    resource: ?*win32.ID3D12Resource = null,
    /// 深度缓冲自带的 1 槽 DSV 堆（非 shader-visible）。
    dsv_heap: ?*win32.ID3D12DescriptorHeap = null,

    /// 颜色纹理：SRV / 采样器在 shader-visible 堆里的静态槽位。
    srv_slot: u32 = 0,
    sampler_slot: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn init(texture_type: TextureType) Texture {
        return .{ .texture_type = texture_type };
    }

    /// 从 RGBA8 像素创建颜色纹理（行优先、无 mip）。
    ///
    /// 内部走主命令表一次性上传：waitForGpu → Reset → 录拷贝+屏障 → 提交 →
    /// waitForGpu。只在加载期调用，不能在帧录制中调用。
    pub fn createRgba8(device: *Device, pixels: []const u8, width: u32, height: u32) !Texture {
        std.debug.assert(pixels.len == @as(usize, width) * height * 4);

        if (device.srv_slots_used >= DeviceSlots.max_srv_slots or
            device.sampler_slots_used >= DeviceSlots.max_sampler_slots)
        {
            return error.TextureSlotsExhausted;
        }

        // 1) 目标纹理：default 堆，PIXEL_SHADER_RESOURCE 起始状态。
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
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = .UNKNOWN,
            .Flags = win32.D3D12_RESOURCE_FLAG_NONE,
        };
        var resource: ?*win32.ID3D12Resource = null;
        try Error.check(
            device.d3d_device.CreateCommittedResource(
                &heap_props,
                win32.D3D12_HEAP_FLAG_NONE,
                &desc,
                win32.D3D12_RESOURCE_STATE_COPY_DEST,
                null,
                win32.IID_ID3D12Resource,
                @ptrCast(&resource),
            ),
            "创建颜色纹理",
        );
        errdefer _ = resource.?.IUnknown.Release();

        // 2) 上传缓冲：行距按硬件 footprint 对齐（256 字节）。
        var footprints: [1]win32.D3D12_PLACED_SUBRESOURCE_FOOTPRINT = undefined;
        var row_counts: [1]u32 = undefined;
        var row_sizes: [1]u64 = undefined;
        var total: u64 = undefined;
        device.d3d_device.GetCopyableFootprints(&desc, 0, 1, 0, &footprints, &row_counts, &row_sizes, &total);
        const footprint = footprints[0];

        var upload = Buffer.init(.upload);
        errdefer upload.deinit();
        try upload.createForUpload(device, @intCast(total));
        @memcpy(upload.mapped_ptr.?[0..pixels.len], pixels);

        // 3) 一次性提交：拷贝 + COPY_DEST → PIXEL_SHADER_RESOURCE。
        device.waitForGpu();
        try Error.check(device.command_allocator.Reset(), "重置命令分配器");
        try Error.check(
            device.command_list.Reset(device.command_allocator, null),
            "重置命令表",
        );

        const src_location = win32.D3D12_TEXTURE_COPY_LOCATION{
            .pResource = upload.resource,
            .Type = .PLACED_FOOTPRINT,
            .Anonymous = .{ .PlacedFootprint = footprint },
        };
        const dst_location = win32.D3D12_TEXTURE_COPY_LOCATION{
            .pResource = resource,
            .Type = .SUBRESOURCE_INDEX,
            .Anonymous = .{ .SubresourceIndex = 0 },
        };
        device.command_list.CopyTextureRegion(&dst_location, 0, 0, 0, &src_location, null);

        const barrier = win32.D3D12_RESOURCE_BARRIER{
            .Type = .TRANSITION,
            .Flags = win32.D3D12_RESOURCE_BARRIER_FLAG_NONE,
            .Anonymous = .{ .Transition = .{
                .pResource = resource,
                .Subresource = win32.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = win32.D3D12_RESOURCE_STATE_COPY_DEST,
                .StateAfter = win32.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,
            } },
        };
        device.command_list.ResourceBarrier(1, @ptrCast(&barrier));

        try Error.check(device.command_list.Close(), "关闭上传命令表");
        var lists = [_]?*win32.ID3D12CommandList{@ptrCast(device.command_list)};
        device.command_queue.ExecuteCommandLists(lists.len, &lists);
        device.waitForGpu();

        // 4) SRV + 采样器写进 shader-visible 堆静态槽位。
        const srv_slot = device.srv_slots_used;
        device.srv_slots_used += 1;
        const sampler_slot = device.sampler_slots_used;
        device.sampler_slots_used += 1;

        const srv_desc = win32.D3D12_SHADER_RESOURCE_VIEW_DESC{
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ViewDimension = win32.D3D12_SRV_DIMENSION_TEXTURE2D,
            // D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING（RGBA 原样）。
            .Shader4ComponentMapping = 0x1688,
            .Anonymous = .{ .Texture2D = .{
                .MostDetailedMip = 0,
                .MipLevels = 1,
                .PlaneSlice = 0,
                .ResourceMinLODClamp = 0.0,
            } },
        };
        device.d3d_device.CreateShaderResourceView(resource, &srv_desc, device.srvCpuHandle(srv_slot));

        const sampler_desc = win32.D3D12_SAMPLER_DESC{
            .Filter = win32.D3D12_FILTER_MIN_MAG_MIP_LINEAR,
            .AddressU = win32.D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            .AddressV = win32.D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            .AddressW = win32.D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            .MipLODBias = 0.0,
            .MaxAnisotropy = 1,
            .ComparisonFunc = win32.D3D12_COMPARISON_FUNC.NEVER,
            .BorderColor = .{ 1, 1, 1, 1 },
            .MinLOD = 0.0,
            .MaxLOD = 0.0,
        };
        device.d3d_device.CreateSampler(&sampler_desc, device.samplerCpuHandle(sampler_slot));

        return .{
            .texture_type = .color_2d,
            .resource = resource,
            .srv_slot = srv_slot,
            .sampler_slot = sampler_slot,
            .width = width,
            .height = height,
        };
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

const Buffer = @import("Buffer.zig").Buffer;
