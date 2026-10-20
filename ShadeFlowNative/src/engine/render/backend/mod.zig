//! 渲染后端入口。
//!
//! 具体后端由 `build.zig` 在编译期选定：它把 `render_backend` 这个 import
//! 指向 `d3d11/mod.zig` 或 `vulkan/mod.zig`。
//!
//! - Windows 默认 `d3d11`，`-Dbackend=vulkan` 时换成 `vulkan`；
//! - Linux / macOS 固定 `vulkan`（macOS 通过 MoltenVK）。
//!
//! 未选中的后端不会进入任何模块的 import 表，所以既不会被分析，也不会触发
//! vulkan-zig 生成绑定。这里只做转发和契约检查。

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
        "setConstants",
        "setTopology",
        "setRasterState",
        "setBlendMode",
        "setDepthState",
        "draw",
        "drawIndexed",
    };

    for (required) |name| {
        if (!@hasDecl(Renderer, name)) {
            @compileError("渲染后端 " ++ capabilities.name ++ " 缺少契约方法: " ++ name);
        }
    }
}
