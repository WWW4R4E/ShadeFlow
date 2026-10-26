//! Vulkan 渲染后端（Windows / Win32、Linux / Wayland、macOS / Metal via MoltenVK）。
//!
//! 帧流程（2 帧 in-flight，D3D12 后端当前是每帧等 GPU 的 1 帧，差异记在
//! 那边）：
//!
//! ```text
//! beginFrame:  等本帧栅栏 → acquire 图像 → 录命令 → clear + 渲染通道开始
//! draw*:       常量写进本帧的缓冲环 → 绑管线/描述符/顶点缓冲 → 录绘制
//! endFrame:    渲染通道结束 → 提交（等 acquire 信号量、发 present 信号量）
//!              → present（等 present 信号量）→ 帧号 +1
//! ```
//!
//! Y 轴翻转、绕序、管线状态的后端差异都记在 `Pipeline.zig` 顶部注释里。

const std = @import("std");
const builtin = @import("builtin");

const vk = @import("vulkan");

const Types = @import("render_types");
const BufferImpl = @import("Buffer.zig").Buffer;
const Descriptor = @import("Descriptor.zig").Descriptor;
const Device = @import("Device.zig").Device;
const Instance = @import("Instance.zig").Instance;
const PipelineImpl = @import("Pipeline.zig").Pipeline;
const pipeline_mod = @import("Pipeline.zig");
const ShaderImpl = @import("Shader.zig").Shader;
const SwapChain = @import("SwapChain.zig").SwapChain;
const Sync = @import("Sync.zig").Sync;
const frames_in_flight = @import("Sync.zig").frames_in_flight;

/// 纹理还没有 Vulkan 实现（深度图在 `SwapChain` 里）。保留占位类型是为了不
/// 让 `render/Renderer.zig` 的门面在两个后端之间出现签名差异。
const TextureImpl = struct {
    pub fn deinit(self: *TextureImpl) void {
        _ = self;
    }
};

pub const Renderer = struct {
    pub const Buffer = BufferImpl;
    pub const Shader = ShaderImpl;
    pub const Texture = TextureImpl;
    pub const Pipeline = PipelineImpl;

    instance: Instance,
    device: Device,
    swap_chain: SwapChain,
    sync: Sync,
    /// 常量缓冲 + 描述符。布局在 init 就建好（着色器要用 pipeline layout），
    /// 环形缓冲在第一次 draw 按数据大小建。
    descriptor: Descriptor,

    width: u32,
    height: u32,

    frame_index: u32 = 0,
    image_index: u32 = 0,
    /// 本帧是否成功开始。`beginFrame` 契约上返回 void，acquire 失败时置 false，
    /// 后续 draw / endFrame 直接跳过，避免往无效命令缓冲里录命令。
    frame_active: bool = false,

    // =========================================================================
    // 初始化
    // =========================================================================

    /// WinUI 3 Composition 模式：Vulkan 后端不支持（见 `mod.zig` 的能力说明）。
    pub fn initForComposition(width: u32, height: u32) !Renderer {
        _ = width;
        _ = height;
        return error.CompositionNotSupported;
    }

    /// 独立窗口模式（原生句柄来自 `optional/Window.zig`）。
    pub fn initForHwnd(native: Types.NativeWindow, width: u32, height: u32) !Renderer {
        var instance = try Instance.init(native, builtin.mode == .debug);
        errdefer instance.deinit();

        var device = try Device.init(&instance);
        errdefer device.deinit();

        const context = SwapChain.Context{
            .shared = device.shared,
            .physical_device = device.physical_device,
            .instance = &instance,
        };

        var swap_chain = try SwapChain.init(context, width, height);
        errdefer swap_chain.deinit();

        var sync = try Sync.init(device.shared);
        errdefer sync.deinit();
        try sync.resizeImageFences(swap_chain.imageCount());

        var descriptor = try Descriptor.init(device.shared, device.minUniformBufferOffsetAlignment());
        errdefer descriptor.deinit();

        std.log.info("Vulkan 渲染管线就绪（{d}x{d}）", .{ swap_chain.extent.width, swap_chain.extent.height });

        return .{
            .instance = instance,
            .device = device,
            .swap_chain = swap_chain,
            .sync = sync,
            .descriptor = descriptor,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.device.shared.wrapper.deviceWaitIdle(self.device.shared.device) catch {};

        self.descriptor.deinit();
        self.sync.deinit();
        self.swap_chain.deinit();
        // 先销毁 device，再销毁 instance：VkDevice 必须在 VkInstance 之前释放。
        self.device.deinit();
        self.instance.deinit();
    }

    // =========================================================================
    // 帧
    // =========================================================================

    pub fn beginFrame(self: *Renderer, clear_color: Types.ClearColor) void {
        self.frame_active = false;
        self.beginFrameInner(clear_color) catch |err| {
            std.log.err("开始 Vulkan 帧失败: {s}", .{@errorName(err)});
        };
    }

    fn beginFrameInner(self: *Renderer, clear_color: Types.ClearColor) !void {
        const shared = self.device.shared;
        const w = &shared.wrapper;
        const frame = self.frame_index % frames_in_flight;

        try self.sync.waitFrame(frame);
        try self.descriptor.beginFrame(frame);

        const acquire = w.acquireNextImageKHR(
            shared.device,
            self.swap_chain.handle,
            std.math.maxInt(u64),
            self.sync.image_available[frame],
            .null,
        ) catch |err| switch (err) {
            // 窗口被缩放/遮挡，交换链失效：重建后跳过这一帧，下一帧自然恢复。
            error.OutOfDateKHR => {
                try self.recreateSwapChain();
                return;
            },
            else => return err,
        };
        self.image_index = acquire.image_index;

        // acquire 可能返回一张上一轮还在飞的图像，等它的栅栏。
        if (self.image_index < self.sync.image_in_flight.len) {
            const pending = self.sync.image_in_flight[self.image_index];
            if (pending != .null) {
                _ = try w.waitForFences(shared.device, &.{pending}, .true, std.math.maxInt(u64));
            }
            self.sync.image_in_flight[self.image_index] = self.sync.in_flight[frame];
        }

        const cmd = self.sync.commandBuffer(frame);
        // 等价于 reset + begin：命令池带 RESET_COMMAND_BUFFER。
        try w.beginCommandBuffer(cmd, &.{});

        const clear_values = [_]vk.ClearValue{
            .{ .color = .{ .float_32 = clear_color } },
            .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };
        w.cmdBeginRenderPass(cmd, &.{
            .render_pass = self.swap_chain.render_pass,
            .framebuffer = self.swap_chain.framebuffer(self.image_index),
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swap_chain.extent,
            },
            .clear_value_count = clear_values.len,
            .p_clear_values = &clear_values,
        }, .@"inline");

        self.applyViewportAndScissor(cmd);
        self.frame_active = true;
    }

    pub fn endFrame(self: *Renderer) void {
        self.endFrameInner() catch |err| {
            std.log.err("结束 Vulkan 帧失败: {s}", .{@errorName(err)});
        };
        self.frame_active = false;
    }

    fn endFrameInner(self: *Renderer) !void {
        if (!self.frame_active) return;

        const shared = self.device.shared;
        const w = &shared.wrapper;
        const frame = self.frame_index % frames_in_flight;
        const cmd = self.sync.commandBuffer(frame);

        w.cmdEndRenderPass(cmd);
        try w.endCommandBuffer(cmd);

        const submit_wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output = true }};
        const acquire_semaphore = [_]vk.Semaphore{self.sync.image_available[frame]};
        const present_semaphore = [_]vk.Semaphore{self.sync.render_finished[frame]};
        const cmds = [_]vk.CommandBuffer{cmd};

        // 复位必须紧贴提交：跳帧路径（acquire 失败）不会走到这里，被复位的
        // 栅栏若无人 signal，下次等到同一帧就永久阻塞。详见 `Sync.waitFrame`。
        try self.sync.resetForSubmit(frame);

        try w.queueSubmit(shared.graphics_queue, &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &acquire_semaphore,
            .p_wait_dst_stage_mask = &submit_wait_stages,
            .command_buffer_count = 1,
            .p_command_buffers = &cmds,
            .signal_semaphore_count = 1,
            .p_signal_semaphores = &present_semaphore,
        }}, self.sync.in_flight[frame]);

        const swapchains = [_]vk.SwapchainKHR{self.swap_chain.handle};
        const image_indices = [_]u32{self.image_index};

        _ = w.queuePresentKHR(shared.present_queue, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &present_semaphore,
            .swapchain_count = 1,
            .p_swapchains = &swapchains,
            .p_image_indices = &image_indices,
        }) catch |err| switch (err) {
            // 与 acquire 同理：交换链失效就重建，不影响下一帧。
            error.OutOfDateKHR => {
                try self.recreateSwapChain();
                self.frame_index += 1;
                return;
            },
            else => return err,
        };

        self.frame_index += 1;
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) !void {
        // 窗口最小化时尺寸为 0，交换链建不出来；等恢复成非 0 再重建。
        if (width == 0 or height == 0) return;

        self.width = width;
        self.height = height;
        try self.recreateSwapChain();
    }

    /// WinUI 侧 `ISwapChainPanelNative::SetSwapChain` 用的裸指针。
    /// Vulkan 不参与 Composition 模式，恒为 null。
    pub fn swapChainInteropHandle(self: *Renderer) ?*anyopaque {
        _ = self;
        return null;
    }

    // =========================================================================
    // 资源工厂
    // =========================================================================

    /// 静态顶点缓冲（device-local + 一次性上传，创建后只读）。
    pub fn createVertexBuffer(
        self: *Renderer,
        data: []const u8,
        stride: u32,
    ) !Buffer {
        return Buffer.createVertexBuffer(self.device.shared, data, stride);
    }

    pub fn createIndexBuffer(self: *Renderer, indices: []const u32) !Buffer {
        return Buffer.createIndexBuffer(self.device.shared, indices);
    }

    pub fn createShaderFromFiles(
        self: *Renderer,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        return Shader.loadProgram(
            .{
                .shared = self.device.shared,
                .pipeline_layout = self.descriptor.pipeline_layout,
                .render_pass = self.swap_chain.render_pass,
            },
            vertex_path,
            pixel_path,
            layout,
        );
    }

    /// 创建管线：着色器 × 状态一次性烤进 `VkPipeline`。
    ///
    /// `shader` 由调用方持有并保证活得比返回的 Pipeline 久。
    pub fn createPipeline(
        self: *Renderer,
        shader: *const Shader,
        state: Types.PipelineState,
    ) !Pipeline {
        // 管线创建只需要 shader 自带的 pipeline context（layout/render pass 都
        // 在加载着色器时定好了），renderer 自身不参与。
        _ = self;
        return PipelineImpl.create(shader, state);
    }

    // =========================================================================
    // 绘制
    // =========================================================================

    pub fn draw(
        self: *Renderer,
        pipeline: *const Pipeline,
        vertex_buffer: *const Buffer,
        vertex_count: u32,
        constants: []const u8,
    ) void {
        self.drawInner(pipeline, vertex_buffer, null, vertex_count, constants) catch |err| {
            std.log.err("Vulkan draw 失败: {s}", .{@errorName(err)});
        };
    }

    pub fn drawIndexed(
        self: *Renderer,
        pipeline: *const Pipeline,
        vertex_buffer: *const Buffer,
        index_buffer: *const Buffer,
        index_count: u32,
        constants: []const u8,
    ) void {
        self.drawInner(pipeline, vertex_buffer, index_buffer, index_count, constants) catch |err| {
            std.log.err("Vulkan drawIndexed 失败: {s}", .{@errorName(err)});
        };
    }

    fn drawInner(
        self: *Renderer,
        pipeline: *const Pipeline,
        vertex_buffer: *const Buffer,
        index_buffer: ?*const Buffer,
        count: u32,
        constants: []const u8,
    ) !void {
        if (!self.frame_active) return;
        const descriptor = &self.descriptor;

        const shared = self.device.shared;
        const w = &shared.wrapper;
        const cmd = self.sync.commandBuffer(self.frame_index % frames_in_flight);

        w.cmdBindPipeline(cmd, .graphics, pipeline.handle);

        // 之所以每个 draw 一个新槽而不是共用一块：命令缓冲是录完再提交的，
        // 共用会让后一个对象的常量覆盖前一个。详见 `Descriptor.zig`。
        var constants_offset: vk.DeviceSize = 0;
        if (constants.len != 0) {
            const frame = self.frame_index % frames_in_flight;
            constants_offset = try descriptor.writeConstants(frame, constants);
        }

        const sets = [_]vk.DescriptorSet{descriptor.currentSet(self.frame_index % frames_in_flight)};
        const dynamic_offsets = [_]u32{@intCast(constants_offset)};
        w.cmdBindDescriptorSets(cmd, .graphics, descriptor.pipeline_layout, 0, &sets, &dynamic_offsets);

        vertex_buffer.bindVertexBuffer(cmd, 0);

        if (index_buffer) |ib| {
            ib.bindIndexBuffer(cmd, .uint32);
            w.cmdDrawIndexed(cmd, count, 1, 0, 0, 0);
        } else {
            w.cmdDraw(cmd, count, 1, 0, 0);
        }
    }

    // =========================================================================
    // 内部
    // =========================================================================

    fn recreateSwapChain(self: *Renderer) !void {
        const context = SwapChain.Context{
            .shared = self.device.shared,
            .physical_device = self.device.physical_device,
            .instance = &self.instance,
        };
        try self.swap_chain.recreate(context, self.width, self.height);
        try self.sync.resizeImageFences(self.swap_chain.imageCount());
    }

    /// 负高度 viewport：把 NDC 的 +Y 映射到屏幕顶部，与 D3D 的视口变换一致，
    /// 相机/矩阵代码因此不需要为 Vulkan 单独改。详见 `Pipeline.zig`。
    fn applyViewportAndScissor(self: *Renderer, cmd: vk.CommandBuffer) void {
        const w = &self.device.shared.wrapper;
        const height: f32 = @floatFromInt(self.swap_chain.extent.height);
        const width: f32 = @floatFromInt(self.swap_chain.extent.width);

        const viewports = [_]vk.Viewport{
            .{ .x = 0.0, .y = height, .width = width, .height = -height, .min_depth = 0.0, .max_depth = 1.0 },
        };
        w.cmdSetViewport(cmd, 0, &viewports);

        const scissors = [_]vk.Rect2D{
            .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_chain.extent },
        };
        w.cmdSetScissor(cmd, 0, &scissors);
    }
};
