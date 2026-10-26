//! VkBuffer + 显存分配。
//!
//! 顶点/索引缓冲：device-local，创建时经 staging buffer 一次性拷过去
//! （几何数据 immutable，上传后再也不改）。常量缓冲：host-visible +
//! host-coherent，CPU 每帧直接写，不需要拷贝。
//!
//! `Buffer` 自己持有 `*const Device.Shared`：`Object.deinit()` 的调用约定是
//! `buffer.deinit()`（由 D3D11 后端的 COM 语义定下），Vulkan 侧要拿到 device
//! 只能自己带着。`Engine.deinit` 先清渲染对象、再销毁 Renderer，所以这个
//! 指针在使用期间一定还活着。

const std = @import("std");

const vk = @import("vulkan");

const Types = @import("render_types");
const Device = @import("Device.zig").Device;

pub const BufferKind = enum { vertex, index, uniform };

pub const Buffer = struct {
    handle: vk.Buffer = .null,
    memory: vk.DeviceMemory = .null,
    /// 分配大小（字节）。
    size: vk.DeviceSize = 0,
    /// host-visible 缓冲的映射指针；device-local 为 null。
    mapped: ?[*]u8 = null,
    /// 跨后端契约：顶点元素数 / 索引数。`Engine` 用它决定 draw 的数量。
    count: u32 = 0,

    shared: ?*const Device.Shared = null,

    // =========================================================================
    // 创建
    // =========================================================================

    /// 静态顶点缓冲：device-local + 一次性上传，创建后只读。
    /// （动态顶点缓冲 host-visible + CPU 直写等真有需求时再加参数分支。）
    pub fn createVertexBuffer(
        shared: *const Device.Shared,
        data: []const u8,
        stride: u32,
    ) !Buffer {
        if (stride == 0) return error.InvalidStride;

        var buffer = try createDeviceLocal(shared, data, .{ .vertex_buffer = true });
        buffer.count = @intCast(data.len / stride);
        return buffer;
    }

    pub fn createIndexBuffer(shared: *const Device.Shared, indices: []const u32) !Buffer {
        var buffer = try createDeviceLocal(shared, std.mem.sliceAsBytes(indices), .{ .index_buffer = true });
        buffer.count = @intCast(indices.len);
        return buffer;
    }

    /// 常量缓冲：host-visible + host-coherent，映射好等 CPU 直接写。
    pub fn createUniform(shared: *const Device.Shared, size: vk.DeviceSize) !Buffer {
        return createHostVisible(shared, size, .{ .uniform_buffer = true });
    }

    pub fn deinit(self: *Buffer) void {
        const shared = self.shared orelse return;
        const w = &shared.wrapper;

        if (self.mapped) |_| {
            w.unmapMemory(shared.device, self.memory);
            self.mapped = null;
        }
        if (self.handle != .null) w.destroyBuffer(shared.device, self.handle, null);
        if (self.memory != .null) w.freeMemory(shared.device, self.memory, null);

        self.handle = .null;
        self.memory = .null;
        self.size = 0;
        self.shared = null;
    }

    // =========================================================================
    // 绑定
    // =========================================================================

    pub fn bindVertexBuffer(self: *const Buffer, cmd: vk.CommandBuffer, first_binding: u32) void {
        const shared = self.shared orelse return;
        const offsets = [_]vk.DeviceSize{0};
        shared.wrapper.cmdBindVertexBuffers(cmd, first_binding, &.{self.handle}, &offsets);
    }

    pub fn bindIndexBuffer(self: *const Buffer, cmd: vk.CommandBuffer, index_type: vk.IndexType) void {
        const shared = self.shared orelse return;
        shared.wrapper.cmdBindIndexBuffer(cmd, self.handle, 0, index_type);
    }

    /// 往 host-visible 缓冲写数据（当前帧尚未提交的区间内调用）。
    pub fn writeAt(self: *Buffer, offset: vk.DeviceSize, data: []const u8) !void {
        const mapped = self.mapped orelse return error.BufferNotHostVisible;
        if (offset + data.len > self.size) return error.BufferTooSmall;
        @memcpy(mapped[offset .. offset + data.len], data);
    }

    // =========================================================================
    // 内部
    // =========================================================================

    /// device-local 缓冲；`data` 经 staging 拷贝上传。
    fn createDeviceLocal(
        shared: *const Device.Shared,
        data: []const u8,
        usage: vk.BufferUsageFlags,
    ) !Buffer {
        const w = &shared.wrapper;

        var staging = try createHostVisible(shared, @intCast(data.len), .{ .transfer_src = true });
        defer staging.deinit();
        try staging.writeAt(0, data);

        var buffer = try create(shared, @intCast(data.len), usage, .{ .device_local = true });
        errdefer buffer.deinit();

        // 一次性命令缓冲：录制拷贝 → 提交 → 等待 → 释放。
        // Zig 没有闭包，直接展开比塞一个拿不到局部变量的回调清楚。
        // staging 在 `defer` 里销毁，所以下面等待期间它还活着。
        // 注意 `allocateCommandBuffers` 要的是 `[*]CommandBuffer`，
        // 单个变量的 `&cmd` 是单指针，得放到数组里。
        var out_cmds: [1]vk.CommandBuffer = undefined;
        try w.allocateCommandBuffers(shared.device, &.{
            .command_pool = shared.transient_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, &out_cmds);
        const cmds = [_]vk.CommandBuffer{out_cmds[0]};
        defer w.freeCommandBuffers(shared.device, shared.transient_pool, &cmds);

        try w.beginCommandBuffer(cmds[0], &.{ .flags = .{ .one_time_submit = true } });
        const regions = [_]vk.BufferCopy{
            .{ .src_offset = 0, .dst_offset = 0, .size = @intCast(data.len) },
        };
        w.cmdCopyBuffer(cmds[0], staging.handle, buffer.handle, &regions);
        try w.endCommandBuffer(cmds[0]);

        try w.queueSubmit(shared.graphics_queue, &[_]vk.SubmitInfo{.{
            .command_buffer_count = 1,
            .p_command_buffers = &cmds,
        }}, .null);
        try w.queueWaitIdle(shared.graphics_queue);

        return buffer;
    }

    /// host-visible 缓冲：创建后立刻映射，`writeAt` 直接改内存。
    /// staging 上传和常量缓冲都走这条路，映射一次就够，不必再单独暴露 map/unmap。
    fn createHostVisible(
        shared: *const Device.Shared,
        size: vk.DeviceSize,
        usage: vk.BufferUsageFlags,
    ) !Buffer {
        var buffer = try create(shared, size, usage, .{ .host_visible = true, .host_coherent = true });
        errdefer buffer.deinit();

        // VK_MEMORY_PROPERTY_HOST_COHERENT_BIT 已要求，不需要手动 flush。
        const mapped = try shared.wrapper.mapMemory(
            shared.device,
            buffer.memory,
            0,
            vk.WHOLE_SIZE,
            .{},
        );
        buffer.mapped = @ptrCast(mapped);
        return buffer;
    }

    fn create(
        shared: *const Device.Shared,
        size: vk.DeviceSize,
        usage: vk.BufferUsageFlags,
        properties: vk.MemoryPropertyFlags,
    ) !Buffer {
        const w = &shared.wrapper;

        const handle = try w.createBuffer(shared.device, &.{
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive,
        }, null);
        errdefer w.destroyBuffer(shared.device, handle, null);

        const requirements = w.getBufferMemoryRequirements(shared.device, handle);
        const memory_type = try shared.findMemoryType(requirements.memory_type_bits, properties);

        const memory = try w.allocateMemory(shared.device, &.{
            .allocation_size = requirements.size,
            .memory_type_index = memory_type,
        }, null);
        errdefer w.freeMemory(shared.device, memory, null);

        try w.bindBufferMemory(shared.device, handle, memory, 0);

        return .{
            .handle = handle,
            .memory = memory,
            .size = requirements.size,
            .shared = shared,
        };
    }
};
