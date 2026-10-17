//! 渲染后端编译期选择。
//!
//! 与 windowkit 的 `platform/mod.zig` 同构：按 `builtin.os.tag` 精确选出一个
//! 后端命名空间，所有调用点直接绑定到它的具体类型。刻意不做运行时 vtable：
//!
//! - 后端只有 2~3 个，类型擦除换不来什么；
//! - 运行时多态会让「后端 A 能编译、后端 B 不能」的问题拖到链接/运行期；
//! - 换 API 的主要成本在 `Engine`/`scene` 是否泄漏后端类型，而不在分派方式。
//!
//! 目标平台 → 后端：
//! - Windows：`d3d11`（`d3d12` 落地后在这里切换）
//! - Linux：  `vulkan`
//!
//! 新增后端时只需实现 `contract.zig` 里列出的方法，`Engine` / `scene` 不改。

const std = @import("std");
const builtin = @import("builtin");

const Types = @import("../Types.zig");

/// 原生窗口句柄。定义在 `Types.zig`，渲染层不依赖 windowkit。
pub const NativeWindow = Types.NativeWindow;

const impl = switch (builtin.os.tag) {
    .windows => @import("d3d11/mod.zig"),
    .linux => @import("vulkan/mod.zig"),
    else => @compileError("不支持的渲染目标平台: " ++ @tagName(builtin.os.tag) ++ "（目前只有 Windows/D3D11 与 Linux/Vulkan）"),
};

pub const Renderer = impl.Renderer;
pub const capabilities = impl.capabilities;

pub const is_windows = builtin.os.tag == .windows;
pub const is_linux = builtin.os.tag == .linux;

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
