//! 渲染后端入口。
//!
//! 具体后端由 `build.zig` 在编译期选定：它把 `render_backend` 这个 import
//! 指向 `d3d12/mod.zig` 或 `vulkan/mod.zig`。
//!
//! - Windows 默认 `d3d12`，`-Dbackend=vulkan` 切换；
//! - Linux / macOS 固定 `vulkan`（macOS 通过 MoltenVK）；
//! - `d3d11/` 已冻结待删：契约以「严格后端」（显式管线）为基线重构后它不再
//!   满足新契约，`-Dbackend=d3d11` 会在这里的契约检查处编译失败。
//!
//! 未选中的后端不会进入任何模块的 import 表，所以既不会被分析，也不会触发
//! vulkan-zig 生成绑定。这里只做转发和契约检查。
//!
//! 契约设计原则：以最严格的后端为基线——管线状态在 `createPipeline` 时定型
//! （D3D12 烘进 PSO、Vulkan 烘进 VkPipeline），每 draw 传常量，没有「随时改
//! 状态」这种即时上下文残留。宽松后端（历史上是 D3D11）适配严格契约很容易，
//! 反过来则要在后端里养缓存。

const builtin = @import("builtin");

const Types = @import("render_types");
const impl = @import("render_backend");

/// 原生窗口句柄。定义在 `Types.zig`，渲染层不依赖 windowkit。
pub const NativeWindow = Types.NativeWindow;

pub const Renderer = impl.Renderer;
pub const capabilities = impl.capabilities;

pub const Kind = Types.BackendKind;
pub const kind = impl.kind;

pub const ShaderFormat = Types.ShaderFormat;
pub const shader_format = impl.shader_format;

pub const is_windows = builtin.os.tag == .windows;
pub const is_linux = builtin.os.tag == .linux;
pub const is_macos = builtin.os.tag == .macos;

/// 当前后端的能力。
pub fn getCapabilities() Types.Capabilities {
    return capabilities;
}

// =============================================================================
// 契约检查：缺方法在编译期就报错，而不是等 Engine 调到才炸
// =============================================================================

comptime {
    const required = [_][]const u8{
        "initForComposition",
        "initForHwnd",
        "deinit",
        "beginFrame",
        "endFrame",
        "resize",
        "swapChainInteropHandle",
        "createVertexBuffer",
        "createIndexBuffer",
        "createShaderFromFiles",
        "createPipeline",
        "draw",
        "drawIndexed",
    };

    for (required) |name| {
        if (!@hasDecl(Renderer, name)) {
            @compileError("渲染后端 " ++ capabilities.name ++ " 缺少契约方法: " ++ name);
        }
    }

    // Pipeline 必须由后端转出（D3D12=PSO，Vulkan=VkPipeline 包装）。
    if (!@hasDecl(Renderer, "Pipeline")) {
        @compileError("渲染后端 " ++ capabilities.name ++ " 缺少 Pipeline 类型");
    }
}
