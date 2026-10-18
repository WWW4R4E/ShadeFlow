//! Vulkan 后端（Linux / Wayland）—— 当前为 M1 骨架。
//!
//! 已完成：
//! - dlopen `libvulkan.so.1` + `vkGetInstanceProcAddr`
//! - VkInstance（Wayland surface + 可选校验层 / debug utils）
//! - 物理设备选择（graphics + present 队列族、`VK_KHR_swapchain`）
//! - VkDevice + graphics/present 队列
//!
//! 尚未实现（下一步按 M1 顺序补）：
//! - SwapChain.zig / Sync.zig：交换链、帧同步
//! - Pipeline.zig / Shader.zig：SPIR-V、render pass、PSO
//! - Buffer.zig / Descriptor.zig：顶点/索引/UBO
//!
//! 骨架阶段 `draw` / `setConstants` 是空操作：窗口能开、相机/拾取可用，
//! 但屏幕上不会出现几何体。

const std = @import("std");
const builtin = @import("builtin");

const Types = @import("../../Types.zig");
const Instance = @import("Instance.zig").Instance;
const Device = @import("Device.zig").Device;

/// 占位资源：M1 骨架阶段只保证上层能持有一个对象。
const BufferImpl = struct {
    pub fn deinit(self: *BufferImpl) void {
        _ = self;
    }
};

const ShaderImpl = struct {
    pub fn deinit(self: *ShaderImpl) void {
        _ = self;
    }
};

const TextureImpl = struct {
    pub fn deinit(self: *TextureImpl) void {
        _ = self;
    }
};

pub const Renderer = struct {
    pub const Buffer = BufferImpl;
    pub const Shader = ShaderImpl;
    pub const Texture = TextureImpl;

    instance: Instance,
    device: Device,
    width: u32,
    height: u32,

    // 管线状态先存起来，等 Pipeline.zig 落地后直接用。
    topology: Types.Topology = .triangle_list,
    raster_state: Types.RasterState = .{ .fill = .solid, .cull = .none },
    depth_state: Types.DepthState = .{},
    blend_mode: Types.BlendMode = .none,

    pub fn initForComposition(width: u32, height: u32) !Renderer {
        _ = width;
        _ = height;
        return error.CompositionNotSupported;
    }

    pub fn initForHwnd(native: Types.NativeWindow, width: u32, height: u32) !Renderer {
        var instance = try Instance.init(native, builtin.mode == .Debug);
        errdefer instance.deinit();

        var device = try Device.init(&instance);
        errdefer device.deinit();

        std.log.info(
            "Vulkan 后端骨架就绪（{d}x{d}）：instance/device/surface 已创建，绘制管线尚未实现",
            .{ width, height },
        );

        return .{
            .instance = instance,
            .device = device,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.device.deinit();
        self.instance.deinit();
    }

    pub fn beginFrame(self: *Renderer, clear_color: Types.ClearColor) void {
        _ = self;
        _ = clear_color;
    }

    pub fn endFrame(self: *Renderer) void {
        _ = self;
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) !void {
        self.width = width;
        self.height = height;
    }

    pub fn swapChainInteropHandle(self: *Renderer) ?*anyopaque {
        _ = self;
        return null;
    }

    // =========================================================================
    // 资源（骨架：占位）
    // =========================================================================

    pub fn createVertexBuffer(
        self: *Renderer,
        data: []const u8,
        stride: u32,
        usage: Types.BufferUsage,
    ) !Buffer {
        _ = self;
        _ = data;
        _ = stride;
        _ = usage;
        return .{};
    }

    pub fn createIndexBuffer(self: *Renderer, indices: []const u16) !Buffer {
        _ = self;
        _ = indices;
        return .{};
    }

    pub fn createShaderFromFiles(
        self: *Renderer,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !Shader {
        _ = self;
        _ = vertex_path;
        _ = pixel_path;
        _ = layout;
        return .{};
    }

    pub fn setConstants(self: *Renderer, data: []const u8) !void {
        _ = self;
        _ = data;
    }

    // =========================================================================
    // 状态
    // =========================================================================

    pub fn setTopology(self: *Renderer, topology: Types.Topology) void {
        self.topology = topology;
    }

    pub fn setRasterState(self: *Renderer, state: Types.RasterState) !void {
        self.raster_state = state;
    }

    pub fn setBlendMode(self: *Renderer, mode: Types.BlendMode) !void {
        self.blend_mode = mode;
    }

    pub fn setDepthState(self: *Renderer, state: Types.DepthState) !void {
        self.depth_state = state;
    }

    // =========================================================================
    // 绘制（骨架：空操作）
    // =========================================================================

    pub fn draw(self: *Renderer, shader: *const Shader, vertex_buffer: *const Buffer, vertex_count: u32) void {
        _ = self;
        _ = shader;
        _ = vertex_buffer;
        _ = vertex_count;
    }

    pub fn drawIndexed(
        self: *Renderer,
        shader: *const Shader,
        vertex_buffer: *const Buffer,
        index_buffer: *const Buffer,
        index_count: u32,
    ) void {
        _ = self;
        _ = shader;
        _ = vertex_buffer;
        _ = index_buffer;
        _ = index_count;
    }
};
