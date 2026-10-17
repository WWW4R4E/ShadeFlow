//! Vulkan 后端（Linux）。
//!
//! ## 当前状态
//!
//! 只落地了与 D3D11 相同的**契约骨架**：方法名、参数类型、返回类型都已对齐，
//! 但内部还没有任何 Vulkan 调用。`initForHwnd` 直接返回
//! `error.BackendNotImplemented`，所以在 Linux 上 `zig build` /
//! `zig build typecheck-linux` 能过，`zig build run` 会在创建引擎时明确失败。
//!
//! 这样做的目的：先把 `Engine` / `scene` 与具体 API 解耦，之后填 Vulkan 实现
//! 时不需要再动上层；也避免在 CI/没有 Vulkan SDK 的机器上误报链接错误。
//!
//! ## 接入顺序（下一步）
//!
//! 1. `vkCreateInstance` + 校验 `VK_KHR_surface` / `VK_KHR_wayland_surface`；
//! 2. 物理设备选择 + `vkCreateDevice`，取 graphics/present 队列族；
//! 3. `Types.NativeWindow.wayland.{display, surface}` →
//!    `vkCreateWaylandSurfaceKHR`；
//! 4. swapchain（`VK_PRESENT_MODE_FIFO_KHR`，`B8G8R8A8_UNORM`/`R8G8B8A8_UNORM`）；
//! 5. command pool + 每帧 command buffer、fence、semaphore；
//! 6. 先把 `createVertexBuffer` / `createShaderFromFiles`（SPIR-V）接上，
//!    再补 `setConstants`（push constant 或 UBO）与 `draw` / `drawIndexed`。
//!
//! 需要注意的差异（D3D11 → Vulkan）：
//! - 没有内置的「设备上下文」：绑定状态与绘制都录进 command buffer；
//! - NDC 深度都是 0..1，但 Vulkan 的 Y 轴向下，需要翻转投影或使用
//!   negative viewport height；
//! - 着色器要 SPIR-V（glslc / dxc -spirv），不能用 fxc 产物；
//! - 资源生命周期靠 fence 管理，`deinit` 前必须 `vkDeviceWaitIdle`。

const Types = @import("../../Types.zig");

// 占位资源：只有 `deinit`，保证 `scene/Object.zig` 与 `Engine` 能通过类型检查。
const PlaceholderBuffer = struct {
    pub fn deinit(self: *PlaceholderBuffer) void {
        _ = self;
    }
};

const PlaceholderShader = struct {
    pub fn deinit(self: *PlaceholderShader) void {
        _ = self;
    }
};

const PlaceholderTexture = struct {
    pub fn deinit(self: *PlaceholderTexture) void {
        _ = self;
    }
};

pub const Buffer = PlaceholderBuffer;
pub const Shader = PlaceholderShader;
pub const Texture = PlaceholderTexture;

pub const capabilities = Types.Capabilities{
    .name = "vulkan",
    // WinUI 的 SwapChainPanel 只认 DXGI 交换链；Vulkan + WinUI 需要
    // external memory / D3D11On12 共享纹理，不属于本后端的 Compose 模式。
    .composition = false,
};

pub const Renderer = struct {
    pub const Buffer = PlaceholderBuffer;
    pub const Shader = PlaceholderShader;
    pub const Texture = PlaceholderTexture;

    width: u32 = 0,
    height: u32 = 0,

    pub fn initForComposition(width: u32, height: u32) !Renderer {
        _ = width;
        _ = height;
        return error.CompositionNotSupported;
    }

    pub fn initForHwnd(native: Types.NativeWindow, width: u32, height: u32) !Renderer {
        _ = native;
        _ = width;
        _ = height;
        return error.BackendNotImplemented;
    }

    pub fn deinit(self: *Renderer) void {
        _ = self;
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

    pub fn createVertexBuffer(
        self: *Renderer,
        data: []const u8,
        stride: u32,
        usage: Types.BufferUsage,
    ) !PlaceholderBuffer {
        _ = self;
        _ = data;
        _ = stride;
        _ = usage;
        return error.BackendNotImplemented;
    }

    pub fn createIndexBuffer(self: *Renderer, indices: []const u16) !PlaceholderBuffer {
        _ = self;
        _ = indices;
        return error.BackendNotImplemented;
    }

    pub fn createShaderFromFiles(
        self: *Renderer,
        vertex_path: []const u8,
        pixel_path: []const u8,
        layout: Types.VertexLayout,
    ) !PlaceholderShader {
        _ = self;
        _ = vertex_path;
        _ = pixel_path;
        _ = layout;
        return error.BackendNotImplemented;
    }

    pub fn setConstants(self: *Renderer, data: []const u8) !void {
        _ = self;
        _ = data;
        return error.BackendNotImplemented;
    }

    pub fn setTopology(self: *Renderer, topology: Types.Topology) void {
        _ = self;
        _ = topology;
    }

    pub fn setRasterState(self: *Renderer, state: Types.RasterState) !void {
        _ = self;
        _ = state;
        return error.BackendNotImplemented;
    }

    pub fn setBlendMode(self: *Renderer, mode: Types.BlendMode) !void {
        _ = self;
        _ = mode;
        return error.BackendNotImplemented;
    }

    pub fn setDepthState(self: *Renderer, state: Types.DepthState) !void {
        _ = self;
        _ = state;
        return error.BackendNotImplemented;
    }

    pub fn draw(self: *Renderer, shader: *const PlaceholderShader, vertex_buffer: *const PlaceholderBuffer, vertex_count: u32) void {
        _ = self;
        _ = shader;
        _ = vertex_buffer;
        _ = vertex_count;
    }

    pub fn drawIndexed(
        self: *Renderer,
        shader: *const PlaceholderShader,
        vertex_buffer: *const PlaceholderBuffer,
        index_buffer: *const PlaceholderBuffer,
        index_count: u32,
    ) void {
        _ = self;
        _ = shader;
        _ = vertex_buffer;
        _ = index_buffer;
        _ = index_count;
    }
};
