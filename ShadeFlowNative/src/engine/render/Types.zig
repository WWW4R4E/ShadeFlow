//! 渲染后端中立的描述类型。
//!
//! 只有这个文件里的类型可以出现在 `scene/`、`Engine.zig` 和 C-ABI 边界上。
//! 任何 `ID3D11*` / `Vk*` 之类的具体 API 类型都必须待在 `backend/<api>/` 里，
//! 由具体后端把它们翻译成自己的描述结构。
//!
//! 枚举值不带显式整型宽度：D3D11/D3D12 与 Vulkan 的对应关系由后端 switch
//! 完成，不要让 UI 或 C# 侧依赖某个后端的具体数值。

const std = @import("std");

// =============================================================================
// 后端
// =============================================================================

/// 当前编译进程序的后端。构建脚本按 `-Dbackend` 直接选模块，所以运行期
/// 不会出现另一种值。
pub const BackendKind = enum { d3d11, vulkan };

/// 着色器二进制格式：D3D11 是 fxc 产出的 DXBC（`.cso`），Vulkan 是 SPIR-V
/// （`.spv`）。`main.zig` 按它选文件后缀。
pub const ShaderFormat = enum { dxbc, spirv };

// =============================================================================
// 缓冲区
// =============================================================================

/// 缓冲区用途。
///
/// - `immutable`：创建后不再修改（几何数据首选）；
/// - `default`：GPU 侧资源，初始化时给一次数据；
/// - `dynamic`：CPU 每帧写入（常量缓冲区）。
pub const BufferUsage = enum {
    immutable,
    default,
    dynamic,
};

/// 图元拓扑。
pub const Topology = enum {
    triangle_list,
    line_list,
    point_list,
};

// =============================================================================
// 管线状态
// =============================================================================

/// 填充模式。
pub const FillMode = enum { solid, wireframe };

/// 三角形剔除模式。
pub const CullMode = enum { none, front, back };

/// 深度/模板比较函数。
pub const CompareFunc = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

/// 深度测试状态。
pub const DepthState = struct {
    depth_test: bool = true,
    write: bool = true,
    compare: CompareFunc = .less,
};

/// 混合模式。
///
/// 目前只有关闭与标准 alpha 混合两种；需要预乘 alpha 或自定义因子时再加
/// 变体，不要在这里塞后端专属的 blend factor。
pub const BlendMode = enum {
    none,
    alpha,
};

/// 光栅化状态。
pub const RasterState = struct {
    fill: FillMode = .solid,
    cull: CullMode = .back,
    /// 逆时针为正面。D3D 的默认是顺时针，Vulkan 默认是逆时针。
    front_counter_clockwise: bool = false,
};

// =============================================================================
// 顶点布局
// =============================================================================

/// 顶点属性格式。
pub const Format = enum {
    f32,
    f32x2,
    f32x3,
    f32x4,
    u32,
    u16,
};

/// 单个顶点属性。
pub const VertexElement = struct {
    /// 语义名（D3D 的 SemanticName / Vulkan 的 attribute 命名约定）。
    semantic: [:0]const u8,
    semantic_index: u32 = 0,
    format: Format,
    /// 相对顶点起始的字节偏移。
    offset: u32,
    input_slot: u32 = 0,
    per_instance: bool = false,
    instance_step_rate: u32 = 0,
};

/// 顶点布局：属性表 + 顶点步长。
pub const VertexLayout = struct {
    elements: []const VertexElement,
    stride: u32,
};

/// 与 `Engine.Vertex`（position: [3]f32 + color: [4]f32）匹配的布局。
pub const position_color = VertexLayout{
    .elements = &[_]VertexElement{
        .{ .semantic = "POSITION", .format = .f32x3, .offset = 0 },
        .{ .semantic = "COLOR", .format = .f32x4, .offset = 12 },
    },
    .stride = 28,
};

/// 位置 + 纹理坐标。目前没有使用，留给 2D/精灵路径。
pub const position_texcoord = VertexLayout{
    .elements = &[_]VertexElement{
        .{ .semantic = "POSITION", .format = .f32x3, .offset = 0 },
        .{ .semantic = "TEXCOORD", .format = .f32x2, .offset = 12 },
    },
    .stride = 20,
};

// =============================================================================
// 原生窗口句柄
// =============================================================================

/// 各平台原生窗口对象。渲染后端从这里取建 surface/swapchain 需要的东西。
///
/// 与 windowkit 的 `NativeHandles` 字段一一对应，但**独立定义**：渲染层不
/// 反向依赖窗口库，窗口适配层负责做一次转换。这样 Linux 渲染分支可以在没有
/// windowkit/wayland 链接项的情况下单独做类型检查。
pub const NativeWindow = union(enum) {
    /// Windows：HWND + HINSTANCE。D3D11/D3D12 只用 hwnd；Vulkan surface 两者都要。
    win32: struct {
        hwnd: *anyopaque,
        hinstance: *anyopaque,
    },
    /// Linux/Wayland：`wl_display` + `wl_surface`（`vkCreateWaylandSurfaceKHR`）。
    wayland: struct {
        display: *anyopaque,
        surface: *anyopaque,
    },
    /// macOS/AppKit：窗口 + 视图 + `CAMetalLayer`。
    appkit: struct {
        ns_window: *anyopaque,
        ns_view: *anyopaque,
        metal_layer: *anyopaque,
    },
    /// Web：surface 完全由 JS 侧持有。
    web: struct {},
};

// =============================================================================
// 帧
// =============================================================================

/// 清屏颜色（RGBA，0..1）。
pub const ClearColor = [4]f32;

/// 后端能力。编译期常量，特性判断可以被折叠。
pub const Capabilities = struct {
    /// 后端名称（日志/调试用）。
    name: []const u8,
    /// 是否支持把交换链交给 WinUI 3 的 `SwapChainPanel`。
    /// 只有 Direct 系列为 true；Vulkan 走 WinUI 需要额外的共享纹理拷贝。
    composition: bool,
};

test "顶点布局的 stride 与字段偏移自洽" {
    const Vertex = extern struct {
        position: [3]f32,
        color: [4]f32,
    };
    try std.testing.expectEqual(@as(u32, @sizeOf(Vertex)), position_color.stride);
    try std.testing.expectEqual(@as(u32, @offsetOf(Vertex, "color")), position_color.elements[1].offset);
}
