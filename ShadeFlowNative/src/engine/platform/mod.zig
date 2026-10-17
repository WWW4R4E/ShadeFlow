//! 引擎的平台相关小工具。
//!
//! 目前只有一件事需要分平台：没有 windowkit 窗口时（DLL/Composition 模式）
//! 由引擎自己排空宿主消息队列。窗口/输入事件循环归 windowkit，不在这里。
//!
//! 与 `render/backend/mod.zig` 一样采用编译期选择：非 Windows 目标不会分析
//! `windows.zig`，因此不会把 `win32` 依赖带进来。

const builtin = @import("builtin");

const impl = switch (builtin.os.tag) {
    .windows => @import("windows.zig"),
    else => @import("null.zig"),
};

/// 排空当前线程的宿主消息队列。返回 false 表示收到退出请求。
pub const pumpMessages = impl.pumpMessages;

/// 渲染后端是否需要由引擎自己排空宿主消息。
///
/// Windows + Composition 由 C# 的 UI 线程驱动，引擎更新时顺手泵消息；
/// 有 windowkit 窗口时走 windowkit 的事件循环，不能重复泵。
pub const needs_manual_pump = builtin.os.tag == .windows;
