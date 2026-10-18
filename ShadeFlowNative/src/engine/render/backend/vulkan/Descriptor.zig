//! 常量缓冲的描述符：set 布局、pipeline layout、池，以及每帧 in-flight 的环形缓冲。
//!
//! 采用 `uniform_buffer_dynamic`：整个帧的常量数据塞进同一块 host-visible 缓冲，
//! 每次 draw 只换 dynamic offset。这样每帧只写一次 descriptor set，draw 之间
//! 不需要任何分配。
//!
//! 为什么必须分槽：命令缓冲是**录完再提交**的，`setConstants` 写的数据要等
//! GPU 真正执行那次 draw 时才被读。如果所有 draw 共用一个槽，后一个对象的
//! 常量会覆盖前一个，画面上只剩最后一个物体的变换。所以按 slot 分段，
//! 并且 slot 之间按 `minUniformBufferOffsetAlignment` 对齐（Vulkan 要求
//! dynamic offset 必须满足该对齐，通常是 256 字节）。
//!
//! 分两段初始化：布局与 pipeline layout 在 `init` 建（着色器在第一次
//! `setConstants` 之前就要用），缓冲与描述符集合在第一次写入时建——那时才
//! 知道常量数据有多大。

const std = @import("std");

const vk = @import("vulkan");

const Buffer = @import("Buffer.zig").Buffer;
const Device = @import("Device.zig").Device;
const frames_in_flight = @import("Sync.zig").frames_in_flight;

/// 初始每帧槽位数。256 个槽 × 对齐后的 slot_size，超出会自动扩容。
const initial_slot_capacity: u32 = 256;

pub const Descriptor = struct {
    shared: *const Device.Shared,
    layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,
    pool: vk.DescriptorPool = .null,

    /// `minUniformBufferOffsetAlignment`：slot 与 dynamic offset 的对齐要求。
    alignment: vk.DeviceSize = 256,
    /// 单个常量数据占用的字节数（已对齐）；首次写入前为 0。
    slot_size: vk.DeviceSize = 0,
    capacity_slots: u32 = 0,
    /// 历史峰值，`beginFrame` 用它决定要不要扩容。
    peak_slots: u32 = 0,

    frames: [frames_in_flight]Frame = @splat(.{}),

    const Frame = struct {
        buffer: Buffer = .{},
        set: vk.DescriptorSet = .null,
        used_slots: u32 = 0,
    };

    /// `alignment` = `minUniformBufferOffsetAlignment`，由后端在 init 时查询，
    /// 因为它决定后续常量缓冲的分槽粒度。
    pub fn init(shared: *const Device.Shared, alignment: vk.DeviceSize) !Descriptor {
        const w = &shared.wrapper;

        const bindings = [_]vk.DescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptor_type = .uniform_buffer_dynamic,
                .descriptor_count = 1,
                .stage_flags = .{ .vertex = true, .fragment = true },
            },
        };

        const layout = try w.createDescriptorSetLayout(shared.device, &.{
            .binding_count = bindings.len,
            .p_bindings = &bindings,
        }, null);
        errdefer w.destroyDescriptorSetLayout(shared.device, layout, null);

        const pipeline_layout = try w.createPipelineLayout(shared.device, &.{
            .set_layout_count = 1,
            .p_set_layouts = &.{layout},
        }, null);
        errdefer w.destroyPipelineLayout(shared.device, pipeline_layout, null);

        return .{
            .shared = shared,
            .layout = layout,
            .pipeline_layout = pipeline_layout,
            .alignment = if (alignment == 0) 256 else alignment,
        };
    }

    pub fn deinit(self: *Descriptor) void {
        const shared = self.shared;
        const w = &shared.wrapper;

        for (&self.frames) |*frame| frame.buffer.deinit();

        if (self.pool != .null) w.destroyDescriptorPool(shared.device, self.pool, null);
        if (self.pipeline_layout != .null) w.destroyPipelineLayout(shared.device, self.pipeline_layout, null);
        if (self.layout != .null) w.destroyDescriptorSetLayout(shared.device, self.layout, null);

        self.pool = .null;
        self.pipeline_layout = .null;
        self.layout = .null;
    }

    /// 开始一帧：必要时按上一帧的峰值扩容，然后复位本帧的写入游标。
    ///
    /// 必须在等完本帧 fence 之后调用（扩容要重建缓冲）。
    pub fn beginFrame(self: *Descriptor, frame_index: u32) !void {
        if (self.capacity_slots == 0) return;
        if (self.peak_slots > self.capacity_slots) try self.resize(self.peak_slots);
        self.frames[frame_index].used_slots = 0;
    }

    /// 写入一帧常量数据，返回本次 draw 要用的 dynamic offset。
    pub fn writeConstants(self: *Descriptor, frame_index: u32, data: []const u8) !vk.DeviceSize {
        if (self.capacity_slots == 0) {
            try self.createPoolAndFrames(
                std.mem.alignForward(u64, data.len, self.alignment),
                initial_slot_capacity,
            );
        }
        if (data.len > self.slot_size) return error.ConstantDataTooLarge;

        const frame = &self.frames[frame_index];
        if (frame.used_slots >= self.capacity_slots) {
            self.peak_slots = @max(self.peak_slots, frame.used_slots + 1);
            return error.ConstantSlotsExhausted;
        }

        const offset: vk.DeviceSize = @as(vk.DeviceSize, frame.used_slots) * self.slot_size;
        frame.used_slots += 1;
        self.peak_slots = @max(self.peak_slots, frame.used_slots);

        try frame.buffer.writeAt(offset, data);
        return offset;
    }

    /// 本帧已分配的 descriptor set（绑定时配合 dynamic offset 使用）。
    pub fn currentSet(self: *const Descriptor, frame_index: u32) vk.DescriptorSet {
        return self.frames[frame_index].set;
    }

    // =========================================================================
    // 内部
    // =========================================================================

    /// 重建池与每帧缓冲。扩容是罕见路径，重建前等 GPU 空闲，
    /// 因为在飞的帧可能还指着旧缓冲。
    fn resize(self: *Descriptor, needed_slots: u32) !void {
        const shared = self.shared;
        try shared.wrapper.deviceWaitIdle(shared.device);

        for (&self.frames) |*frame| frame.buffer.deinit();
        shared.wrapper.destroyDescriptorPool(shared.device, self.pool, null);

        self.peak_slots = 0;
        try self.createPoolAndFrames(self.slot_size, needed_slots);

        std.log.info("常量缓冲扩容：每帧 {d} 个槽位（{d} 字节/槽）", .{
            self.capacity_slots,
            self.slot_size,
        });
    }

    fn createPoolAndFrames(self: *Descriptor, slot_size: vk.DeviceSize, capacity_slots: u32) !void {
        const shared = self.shared;
        const w = &shared.wrapper;

        self.slot_size = slot_size;
        self.capacity_slots = capacity_slots;
        const buffer_size = slot_size * capacity_slots;

        const pool_sizes = [_]vk.DescriptorPoolSize{
            .{ .type = .uniform_buffer_dynamic, .descriptor_count = frames_in_flight },
        };

        self.pool = try w.createDescriptorPool(shared.device, &.{
            .max_sets = frames_in_flight,
            .pool_size_count = pool_sizes.len,
            .p_pool_sizes = &pool_sizes,
        }, null);

        for (&self.frames) |*frame| {
            frame.buffer = try Buffer.createUniform(shared, buffer_size);

            var out_sets: [1]vk.DescriptorSet = undefined;
            try w.allocateDescriptorSets(shared.device, &.{
                .descriptor_pool = self.pool,
                .descriptor_set_count = 1,
                .p_set_layouts = &.{self.layout},
            }, &out_sets);
            const set = out_sets[0];
            frame.set = set;

            // 这版 vulkan-zig 的 WriteDescriptorSet 三个指针字段都是非可选的
            // many-pointer，但驱动只会读与 descriptor_type 匹配的那一个，
            // 其余给合法空值即可。数组是为了满足 many-pointer 的类型要求。
            const dummy_images = [_]vk.DescriptorImageInfo{std.mem.zeroes(vk.DescriptorImageInfo)};
            const dummy_views = [_]vk.BufferView{.null};
            const buffer_info = [_]vk.DescriptorBufferInfo{
                .{ .buffer = frame.buffer.handle, .offset = 0, .range = vk.WHOLE_SIZE },
            };

            w.updateDescriptorSets(shared.device, &.{
                .{
                    .dst_set = set,
                    .dst_binding = 0,
                    .dst_array_element = 0,
                    .descriptor_count = 1,
                    .descriptor_type = .uniform_buffer_dynamic,
                    .p_image_info = &dummy_images,
                    .p_buffer_info = &buffer_info,
                    .p_texel_buffer_view = &dummy_views,
                },
            }, null);
        }
    }
};
