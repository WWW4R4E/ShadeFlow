//! 帧同步：command pool / command buffer、acquire 与 present 信号量、in-flight 栅栏。
//!
//! Vulkan 没有 D3D11 那种「提交后由驱动排队」的语义，CPU 必须自己同步：
//!
//! - `image_available[frame]`：`acquireNextImageKHR` 等它，表示交换链图像可以写了；
//! - `render_finished[frame]`：`queuePresentKHR` 等它，表示这一帧确实画完了；
//! - `in_flight[frame]`：CPU 与「这一帧提交的工作」同步，`beginFrame` 等它，
//!   等到了才能重用该帧的命令缓冲和常量缓冲槽位；
//! - `image_in_flight[image]`：每张交换链图像被哪个栅栏占用。acquire 可能返回
//!   一张上一轮还在飞的图像（比如 mailbox 模式），不等它就会写到正在被读的内存。

const std = @import("std");

const vk = @import("vulkan");

const Device = @import("Device.zig").Device;

/// 同时在飞的帧数。2 是常见取值：CPU 录制第 N+1 帧时 GPU 正在画第 N 帧。
pub const frames_in_flight: u32 = 2;

pub const Sync = struct {
    shared: *const Device.Shared,
    pool: vk.CommandPool,
    /// `vk.CommandBuffer` 是非空指针（`*opaque{}`），不能用 `.null` 初始化。
    command_buffers: [frames_in_flight]vk.CommandBuffer = undefined,
    image_available: [frames_in_flight]vk.Semaphore = @splat(.null),
    render_finished: [frames_in_flight]vk.Semaphore = @splat(.null),
    in_flight: [frames_in_flight]vk.Fence = @splat(.null),

    /// 长度 = 交换链图像数，重建交换链时重新分配。
    image_in_flight: []vk.Fence = &.{},

    pub fn init(shared: *const Device.Shared) !Sync {
        const w = &shared.wrapper;

        const pool = try w.createCommandPool(shared.device, &.{
            // 每帧重录，需要 RESET_COMMAND_BUFFER；也可整池 reset，用后者。
            .flags = .{ .reset_command_buffer = true },
            .queue_family_index = shared.graphics_family,
        }, null);
        errdefer w.destroyCommandPool(shared.device, pool, null);

        var self = Sync{ .shared = shared, .pool = pool };
        errdefer self.deinit();

        var cmd: [frames_in_flight]vk.CommandBuffer = undefined;
        try w.allocateCommandBuffers(shared.device, &.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = frames_in_flight,
        }, &cmd);
        self.command_buffers = cmd;

        for (&self.image_available) |*semaphore| {
            semaphore.* = try w.createSemaphore(shared.device, &.{}, null);
        }
        for (&self.render_finished) |*semaphore| {
            semaphore.* = try w.createSemaphore(shared.device, &.{}, null);
        }
        // 手动 reset：beginFrame 用 RESET_FENCE 而不是先 wait 再 create。
        for (&self.in_flight) |*fence| {
            fence.* = try w.createFence(shared.device, &.{ .flags = .{ .signaled = true } }, null);
        }

        return self;
    }

    pub fn deinit(self: *Sync) void {
        const shared = self.shared;
        const w = &shared.wrapper;

        w.deviceWaitIdle(shared.device) catch {};

        for (&self.in_flight) |*fence| {
            if (fence.* != .null) w.destroyFence(shared.device, fence.*, null);
        }
        for (&self.render_finished) |*semaphore| {
            if (semaphore.* != .null) w.destroySemaphore(shared.device, semaphore.*, null);
        }
        for (&self.image_available) |*semaphore| {
            if (semaphore.* != .null) w.destroySemaphore(shared.device, semaphore.*, null);
        }
        if (self.pool != .null) w.destroyCommandPool(shared.device, self.pool, null);

        if (self.image_in_flight.len != 0) std.heap.page_allocator.free(self.image_in_flight);
        self.image_in_flight = &.{};
        self.pool = .null;
    }

    /// 交换链重建后调用：图像数变了，占用表跟着变。
    pub fn resizeImageFences(self: *Sync, image_count: u32) !void {
        const allocator = std.heap.page_allocator;
        if (self.image_in_flight.len != 0) allocator.free(self.image_in_flight);
        self.image_in_flight = try allocator.alloc(vk.Fence, image_count);
        @memset(self.image_in_flight, .null);
    }

    /// 等待某帧的栅栏，但**不复位**。
    ///
    /// 复位必须推迟到 `endFrame` 提交之前（见 `resetForSubmit`）：如果
    /// `beginFrame` 里 `acquire` 返回 `OutOf_DATE_KHR` 提前返回，这一帧不会提交，
    /// 一个已被复位的栅栏就再也没人 signal，下次等到同一帧时 `waitForFences`
    /// 会永久阻塞，画面直接冻死。
    pub fn waitFrame(self: *const Sync, frame_index: u32) !void {
        const shared = self.shared;
        _ = try shared.wrapper.waitForFences(
            shared.device,
            &.{self.in_flight[frame_index]},
            .true,
            std.math.maxInt(u64),
        );
    }

    /// 提交前复位栅栏：`queueSubmit` 要求 fence 处于未触发状态。
    pub fn resetForSubmit(self: *const Sync, frame_index: u32) !void {
        const shared = self.shared;
        try shared.wrapper.resetFences(shared.device, &.{self.in_flight[frame_index]});
    }

    pub fn commandBuffer(self: *const Sync, frame_index: u32) vk.CommandBuffer {
        return self.command_buffers[frame_index];
    }
};
