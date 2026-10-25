//! windowkit 原生句柄 → 渲染层中立句柄。
//!
//! 两边字段一一对应；转换放在宿主侧，渲染层因此不需要 import windowkit，
//! Linux 分支也能脱离 wayland 链接项单独做类型检查。

const windowkit = @import("windowkit");

const NativeWindow = @import("shadeflow_engine").NativeWindow;

pub fn convertNativeHandles(handles: windowkit.NativeHandles) NativeWindow {
    return switch (handles) {
        .win32 => |h| .{ .win32 = .{ .hwnd = h.hwnd, .hinstance = h.hinstance } },
        .wayland => |h| .{ .wayland = .{ .display = h.display, .surface = h.surface } },
        .appkit => |h| .{ .appkit = .{
            .ns_window = h.ns_window,
            .ns_view = h.ns_view,
            .metal_layer = h.metal_layer,
        } },
    };
}
