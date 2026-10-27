//! 渲染后端中立的描述类型。
//!
//! 只有这个文件里的类型可以出现在 `scene/`、`Engine.zig` 和 C-ABI 边界上。
//! 任何 `ID3D11*` / `Vk*` 之类的具体 API 类型都必须待在 `backend/<api>/` 里，
//! 由具体后端把它们翻译成自己的描述结构。
//!
//! 枚举值不带显式整型宽度：D3D12 与 Vulkan 的对应关系由后端 switch
//! 完成，不要让 UI 或 C# 侧依赖某个后端的具体数值。

const std = @import("std");

// =============================================================================
// 后端
// =============================================================================

/// 当前编译进程序的后端。构建脚本按 `-Dbackend` 直接选模块，所以运行期
/// 不会出现另一种值。
pub const BackendKind = enum { d3d12, vulkan };

/// 着色器二进制格式：D3D12 是 dxc 产出的 DXBC/DXIL（`.cso`），Vulkan 是
/// SPIR-V（`.spv`）。`main.zig` 按它选文件后缀。
pub const ShaderFormat = enum { dxbc, spirv };

// =============================================================================
// 图元拓扑
// =============================================================================

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

/// 显式管线的不变状态：创建 `Pipeline` 时整体定型，绘制期间不可变。
///
/// 这是契约以「严格后端」为基线的结果——D3D12 烘进 PSO、Vulkan 烘进
/// `VkPipeline`，不存在「随时改状态」这个操作。默认值是重构前两个后端的
/// **实际生效状态**（历史默认值，Engine 从不覆盖）。
/// 注意 `cull` 是 `.none` 而不是 `RasterState` 的结构体默认 `.back`：几何
/// 生成器的面绕序还没按 D3D 约定审计过，贸然开背面剔除会把正面剔掉
/// （表现为立方体「破洞」、后面的物体透出来，像遮挡错误）。
pub const PipelineState = struct {
    raster: RasterState = .{ .fill = .solid, .cull = .none },
    depth: DepthState = .{},
    blend: BlendMode = .none,
    topology: Topology = .triangle_list,
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

// =============================================================================
// 顶点
// =============================================================================

/// 顶点结构，与着色器中的定义匹配。
///
/// 放在这里而不是 `Engine.zig`：它是**渲染层中立的顶点格式**，`scene/` 侧的
/// 几何生成器也要用它，放引擎根会让 `scene/` 反向依赖引擎根（文件级循环）。
pub const Vertex = struct {
    position: [3]f32,
    color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    /// 世界空间法线（建模空间），光照用。默认朝上：线段/矩形这类「片」
    /// 状几何没有明确法线，按顶面受光处理。
    normal: [3]f32 = .{ 0.0, 1.0, 0.0 },
};

/// 与 `Vertex`（position + color + normal）匹配的布局。
pub const position_color = VertexLayout{
    .elements = &[_]VertexElement{
        .{ .semantic = "POSITION", .format = .f32x3, .offset = 0 },
        .{ .semantic = "COLOR", .format = .f32x4, .offset = 12 },
        .{ .semantic = "NORMAL", .format = .f32x3, .offset = 28 },
    },
    .stride = 40,
};

/// 位置 + 纹理坐标（带纹理管线的顶点格式）。颜色来自纹理采样 × gColor。
pub const VertexTex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
};

/// 与 `VertexTex`（position + normal + uv）匹配的布局。
pub const position_texcoord = VertexLayout{
    .elements = &[_]VertexElement{
        .{ .semantic = "POSITION", .format = .f32x3, .offset = 0 },
        .{ .semantic = "NORMAL", .format = .f32x3, .offset = 12 },
        .{ .semantic = "TEXCOORD", .format = .f32x2, .offset = 24 },
    },
    .stride = 32,
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
    /// Windows：HWND + HINSTANCE。D3D12 只用 hwnd；Vulkan surface 两者都要。
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
    // 刻意用独立的 extern struct 复算一遍，不引用上面的 Vertex 本身。
    const VertexExt = extern struct {
        position: [3]f32,
        color: [4]f32,
        normal: [3]f32,
    };
    try std.testing.expectEqual(@as(u32, @sizeOf(VertexExt)), position_color.stride);
    try std.testing.expectEqual(@as(u32, @offsetOf(VertexExt, "color")), position_color.elements[1].offset);
    try std.testing.expectEqual(@as(u32, @offsetOf(VertexExt, "normal")), position_color.elements[2].offset);

    // 带纹理顶点：position(12) + normal(12) + uv(8) = 32。
    const VertexTexExt = extern struct { position: [3]f32, normal: [3]f32, uv: [2]f32 };
    try std.testing.expectEqual(@as(u32, @sizeOf(VertexTexExt)), position_texcoord.stride);
    try std.testing.expectEqual(@as(u32, 12), position_texcoord.elements[1].offset);
    try std.testing.expectEqual(@as(u32, 24), position_texcoord.elements[2].offset);

    // 顶点色：position(12) + color(16) + normal(12) = 40。
    const VertexNrmExt = extern struct { position: [3]f32, color: [4]f32, normal: [3]f32 };
    try std.testing.expectEqual(@as(u32, @sizeOf(VertexNrmExt)), position_color.stride);
    try std.testing.expectEqual(@as(u32, 28), position_color.elements[2].offset);

}
