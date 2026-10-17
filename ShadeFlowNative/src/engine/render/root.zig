//! 渲染层独立入口。
//!
//! 用途：`zig build typecheck-linux` 只分析 `render/`（含 Vulkan 骨架），
//! 不引入 windowkit/Wayland 链接项。完整 Linux 构建仍然走 `src/root.zig`。
//!
//! 这里用 `comptime` 引用所有契约方法，确保“只声明没实现”的函数也会被
//! 类型检查，而不是因为没人调用被 Zig 的惰性分析跳过。

pub const Renderer = @import("Renderer.zig").Renderer;
pub const Types = @import("Renderer.zig").Types;
pub const backend = @import("backend/mod.zig");

comptime {
    const R = backend.Renderer;

    _ = R.initForComposition;
    _ = R.initForHwnd;
    _ = R.deinit;
    _ = R.beginFrame;
    _ = R.endFrame;
    _ = R.resize;
    _ = R.swapChainInteropHandle;
    _ = R.createVertexBuffer;
    _ = R.createIndexBuffer;
    _ = R.createShaderFromFiles;
    _ = R.setConstants;
    _ = R.setTopology;
    _ = R.setRasterState;
    _ = R.setBlendMode;
    _ = R.setDepthState;
    _ = R.draw;
    _ = R.drawIndexed;

    _ = backend.capabilities;
}
