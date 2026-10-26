//! Vulkan 纹理：RGBA8 → device-local image → view + sampler → set1 描述符。
//!
//! 上传走 `Shared.transient_pool` 的一次性命令缓冲（staging → 拷贝 → 布局
//! 转移），与 Buffer 的路径同款。创建是加载期低频操作，`queueWaitIdle`
//! 等待可接受。set1 描述符在创建时写好，绘制期只换绑定。

const std = @import("std");

const vk = @import("vulkan");

const Device = @import("Device.zig").Device;
const Descriptor = @import("Descriptor.zig").Descriptor;
const Buffer = @import("Buffer.zig").Buffer;

pub const TextureType = enum { color_2d, depth_stencil };

pub const Texture = struct {
    texture_type: TextureType,
    shared: ?*const Device.Shared = null,
    image: vk.Image = .null,
    memory: vk.DeviceMemory = .null,
    view: vk.ImageView = .null,
    sampler: vk.Sampler = .null,
    /// set1 描述符（combined image sampler），绘制时绑定。
    set: vk.DescriptorSet = .null,
    width: u32 = 0,
    height: u32 = 0,

    /// 深度缓冲占位（深度图当前在 SwapChain 里创建）。
    pub fn init(texture_type: TextureType) Texture {
        return .{ .texture_type = texture_type };
    }

    /// 从 RGBA8 像素创建颜色纹理（像素行优先、无 mip）。
    pub fn createRgba8(
        shared: *const Device.Shared,
        descriptor: *Descriptor,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) !Texture {
        std.debug.assert(pixels.len == @as(usize, width) * height * 4);
        const w = &shared.wrapper;

        const extent = vk.Extent3D{ .width = width, .height = height, .depth = 1 };

        // 目标 image：device-local + 采样目标 + 传输目标。
        const image = try w.createImage(shared.device, &.{
            .image_type = .@"2d",
            .extent = extent,
            .mip_levels = 1,
            .array_layers = 1,
            .format = .r8g8b8a8_unorm,
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = .{ .transfer_dst = true, .sampled = true },
            .sharing_mode = .exclusive,
            .samples = .{ .@"1" = true },
        }, null);
        errdefer w.destroyImage(shared.device, image, null);

        const requirements = w.getImageMemoryRequirements(shared.device, image);
        const memory_type = try shared.findMemoryType(requirements.memory_type_bits, .{ .device_local = true });
        const memory = try w.allocateMemory(shared.device, &.{
            .allocation_size = requirements.size,
            .memory_type_index = memory_type,
        }, null);
        errdefer w.freeMemory(shared.device, memory, null);
        try w.bindImageMemory(shared.device, image, memory, 0);

        // staging + 一次性命令缓冲拷贝 + 布局转移。
        var staging = try Buffer.createHostVisible(shared, pixels.len, .{ .transfer_src = true });
        defer staging.deinit();
        try staging.writeAt(0, pixels);

        var out_cmds: [1]vk.CommandBuffer = undefined;
        try w.allocateCommandBuffers(shared.device, &.{
            .command_pool = shared.transient_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, &out_cmds);
        const cmds = [_]vk.CommandBuffer{out_cmds[0]};
        defer w.freeCommandBuffers(shared.device, shared.transient_pool, &cmds);

        try w.beginCommandBuffer(cmds[0], &.{ .flags = .{ .one_time_submit = true } });

        // UNDEFINED → TRANSFER_DST。
        w.cmdPipelineBarrier(cmds[0], .{ .top_of_pipe = true }, .{ .transfer = true }, .{}, &.{}, &.{}, &.{
            imageBarrier(image, .undefined, .transfer_dst_optimal),
        });

        const regions = [_]vk.BufferImageCopy{
            .{
                .buffer_offset = 0,
                .buffer_row_length = 0, // 0 = 紧密打包
                .buffer_image_height = 0,
                .image_subresource = .{ .aspect_mask = .{ .color = true }, .mip_level = 0, .base_array_layer = 0, .layer_count = 1 },
                .image_offset = .{ .x = 0, .y = 0, .z = 0 },
                .image_extent = extent,
            },
        };
        w.cmdCopyBufferToImage(cmds[0], staging.handle, image, .transfer_dst_optimal, &regions);

        // TRANSFER_DST → SHADER_READ_ONLY。
        w.cmdPipelineBarrier(cmds[0], .{ .transfer = true }, .{ .fragment_shader = true }, .{}, &.{}, &.{}, &.{
            imageBarrier(image, .transfer_dst_optimal, .shader_read_only_optimal),
        });

        try w.endCommandBuffer(cmds[0]);
        try w.queueSubmit(shared.graphics_queue, &[_]vk.SubmitInfo{.{
            .command_buffer_count = 1,
            .p_command_buffers = &cmds,
        }}, .null);
        try w.queueWaitIdle(shared.graphics_queue);

        // view + sampler。
        const view = try w.createImageView(shared.device, &.{
            .image = image,
            .view_type = .@"2d",
            .format = .r8g8b8a8_unorm,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{ .aspect_mask = .{ .color = true }, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 },
        }, null);
        errdefer w.destroyImageView(shared.device, view, null);

        const sampler = try w.createSampler(shared.device, &.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_mode = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .mip_lod_bias = 0.0,
            .anisotropy_enable = .false,
            .max_anisotropy = 1.0,
            .compare_enable = .false,
            .compare_op = .never,
            .min_lod = 0.0,
            .max_lod = 0.0,
            .border_color = .float_opaque_white,
            .unnormalized_coordinates = .false,
        }, null);
        errdefer w.destroySampler(shared.device, sampler, null);

        // set1 描述符（创建时写好）。
        const set = try descriptor.allocTextureSet(view, sampler);

        return .{
            .texture_type = .color_2d,
            .shared = shared,
            .image = image,
            .memory = memory,
            .view = view,
            .sampler = sampler,
            .set = set,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Texture) void {
        const shared = self.shared orelse return;
        const w = &shared.wrapper;

        if (self.sampler != .null) w.destroySampler(shared.device, self.sampler, null);
        if (self.view != .null) w.destroyImageView(shared.device, self.view, null);
        if (self.image != .null) w.destroyImage(shared.device, self.image, null);
        if (self.memory != .null) w.freeMemory(shared.device, self.memory, null);

        self.sampler = .null;
        self.view = .null;
        self.image = .null;
        self.memory = .null;
        self.shared = null;
    }

    fn imageBarrier(image: vk.Image, from: vk.ImageLayout, to: vk.ImageLayout) vk.ImageMemoryBarrier {
        return .{
            .old_layout = from,
            .new_layout = to,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{ .aspect_mask = .{ .color = true }, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 },
            // 同一队列独占使用，访问掩码按惯例给足即可。
            .src_access_mask = if (from == .undefined) .{} else .{ .transfer_write = true },
            .dst_access_mask = if (to == .shader_read_only_optimal) .{ .shader_read = true } else .{ .transfer_write = true },
        };
    }
};