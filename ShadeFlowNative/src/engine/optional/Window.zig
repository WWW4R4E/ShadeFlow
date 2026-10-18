//! 窗口适配层 —— 包装 windowkit（https://github.com/WWW4R4E/windowkit）。
//!
//! windowkit 是 GLFW 式纯窗口库：窗口创建/销毁、事件循环、输入/IME/DPI、
//! 文件拖放、vsync 帧节拍，渲染归接入方。本模块把 windowkit 的
//! `Platform` / `PlatformWindow` 适配成引擎内部的 `Window` 接口：输入事件
//! 翻译进 `Input` 状态结构，尺寸变化通过 `size_changed` 标志同步，事件循环
//! 和帧节拍交给 `plat.run()`。
//!
//! 原生句柄原样交给渲染后端（Windows/HWND、Linux/Wayland display+surface），
//! 本层不解释它们。
//!
//! Windows 后端契约（见 windowkit README）：
//! - 消息泵、输入回调、渲染回调全部串行在 UI 线程，无需加锁；
//! - 渲染回调每 `DwmFlush` 节拍派发一次（DWM 禁用退化为 16ms 睡眠），
//!   每次派发后需要 `requestRender()` 重新预约下一帧（连续渲染模式）。

const std = @import("std");

const windowkit = @import("windowkit");
const wkInput = windowkit.input;

const Input = @import("Input.zig").Input;
const Engine = @import("../Engine.zig").Engine;
const render_api = @import("../render/Renderer.zig");

pub const Window = struct {
    allocator: std.mem.Allocator,
    plat: windowkit.Platform = undefined,
    win: ?*windowkit.PlatformWindow = null,
    /// 平台原生句柄（HWND / wl_display+wl_surface / …），已转换成渲染层的中立
    /// union。渲染后端用它建 surface。
    native_handles: ?render_api.NativeWindow = null,
    running: bool = true,
    size_changed: bool = false,
    input: Input,
    engine: ?*Engine = null,

    pub fn init(allocator: std.mem.Allocator) !*Window {
        const self = try allocator.create(Window);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .input = Input.init(),
        };

        try self.plat.initInPlace(allocator);
        errdefer self.plat.deinit();

        const options: windowkit.WindowOptions = .{
            .title = "ShadeFlow",
            .width = 900,
            .height = 600,
            .centered = true,
            .file_drop = true,
            // .min_size = .{ .width = 700, .height = 600 },
            .max_size = .{ .width = 1600, .height = 900 },
        };

        self.win = try windowkit.PlatformWindow.init(allocator, &self.plat, &options);
        errdefer self.win.?.deinit();

        // 原生句柄：交给渲染后端建 surface / swapchain。
        self.native_handles = convertNativeHandles(self.win.?.nativeHandles());

        // 回调：输入 → Input 状态，关闭 → 退出循环，resize → size_changed。
        self.win.?.setUserData(self);
        self.win.?.setInputCallback(inputTrampoline);
        self.win.?.setCloseCallback(closeTrampoline);
        self.win.?.setResizeCallback(resizeTrampoline);

        // 补一次 resize 信号：windowkit init 内部已 ShowWindow 并触发过
        // WM_SIZE，但那时 resize 回调还没挂上；引擎第一次 update 要靠
        // size_changed 走 handleResize → resizeRenderer，把 Engine.viewport
        // 建起来（Picker 点击选取依赖它），否则点击永远选不中。
        self.size_changed = true;

        return self;
    }

    pub fn deinit(self: *Window) void {
        // 契约：先销毁渲染资源（swapchain 已在 Engine.deinit 销毁），再关窗口。
        if (self.win) |win| win.deinit();
        self.win = null;
        self.plat.deinit();
        self.allocator.destroy(self);
    }

    /// windowkit 的 PlatformWindow（给主循环设置渲染回调等）。
    pub fn platform_window(self: *Window) ?*windowkit.PlatformWindow {
        return self.win;
    }

    /// 原生窗口句柄，交给渲染后端。
    pub fn nativeHandles(self: *Window) ?render_api.NativeWindow {
        return self.native_handles;
    }

    /// 客户区物理像素尺寸（swapchain 用它；PerMonitorV2 下是真实物理值）。
    pub fn getClientSize(self: *Window) struct { width: u32, height: u32 } {
        const win = self.win orelse return .{ .width = 0, .height = 0 };
        const px = win.framebufferSize();
        return .{ .width = px.width_px, .height = px.height_px };
    }

    /// windowkit 平台层已按 PerMonitorV2 初始化进程，且窗口创建时即展示，
    /// 无需额外操作。
    pub fn show(self: *Window) void {
        _ = self;
    }

    /// 阻塞事件循环：泵 Win32 消息，每个 DwmFlush 节拍回调一次 `engine.render`。
    /// 在 `engine.update` 里的输入驱动也挂在这个回调链上。
    pub fn run(self: *Window, engine: *Engine) !void {
        const win = self.win orelse return error.WindowNotInitialized;
        self.engine = engine;
        win.setRenderCallback(renderTrampoline);
        self.plat.run();
    }

    pub fn getInput(self: *Window) *Input {
        return &self.input;
    }

    pub fn isRunning(self: *const Window) bool {
        return self.running;
    }

    // =========================================================================
    // 回调
    // =========================================================================

    fn renderTrampoline(win: *windowkit.PlatformWindow) void {
        const self = win.getUserData(Window) orelse return;
        const engine = self.engine orelse return;
        const keep_running = engine.update() catch blk: {
            std.debug.print("engine update 失败\n", .{});
            break :blk true;
        };
        if (!keep_running) {
            win.getPlatform().quit();
            return;
        }
        engine.render();
        // 连续渲染：预约下一帧节拍（需要 needs_render 重新置位）。
        win.requestRender();
    }

    fn closeTrampoline(win: *windowkit.PlatformWindow) bool {
        _ = win;
        return true; // 放行关闭；事件循环因窗口全关而结束。
    }

    fn resizeTrampoline(win: *windowkit.PlatformWindow, width: f64, height: f64) void {
        const self = win.getUserData(Window) orelse return;
        // windowkit 传的是逻辑像素，这里只做诊断；引擎侧统一用
        // `getClientSize()`（物理像素）重建交换链，两者都打出来方便对照。
        const fb = win.framebufferSize();
        std.log.info(
            "窗口尺寸变化：逻辑 {d:.0}x{d:.0}，物理 {d}x{d}（scale {d:.2}）",
            .{ width, height, fb.width_px, fb.height_px, win.getScaleFactor() },
        );
        self.size_changed = true;
    }

    fn inputTrampoline(win: *windowkit.PlatformWindow, event: wkInput.InputEvent) bool {
        const self = win.getUserData(Window) orelse return false;
        return self.translateEvent(event);
    }

    // =========================================================================
    // 事件翻译：windowkit InputEvent → 引擎 Input 状态
    // =========================================================================

    /// 鼠标坐标：引擎的选取（Picker）用物理像素做视口对比。
    ///
    /// 后端差异（经验证）：
    /// - Windows：windowkit 直发 `WM_MOUSEMOVE` 的 lParam 客户区坐标，
    ///   PerMonitorV2 下该值就是**物理像素**，不要再乘 scale；
    /// - 若将来接 macOS/Linux（坐标为逻辑像素），在这里乘 `getScaleFactor()`。
    fn toEnginePx(self: *Window, x: f64, y: f64) struct { x: i32, y: i32 } {
        _ = self;
        return .{
            .x = @intFromFloat(@round(x)),
            .y = @intFromFloat(@round(y)),
        };
    }

    fn translateEvent(self: *Window, event: wkInput.InputEvent) bool {
        switch (event) {
            .mouse_moved, .mouse_dragged => |m| {
                const pos = self.toEnginePx(m.position.x, m.position.y);
                self.input.onMouseMove(pos.x, pos.y, m.modifiers);
            },
            .mouse_down => |m| self.input.onMouseButton(m.button, true, m.modifiers),
            .mouse_up => |m| self.input.onMouseButton(m.button, false, m.modifiers),
            .scroll => |s| self.input.onScroll(s.delta.y, s.modifiers),
            .key_down => |k| self.input.onKey(k.key, true, k.modifiers),
            .key_up => |k| self.input.onKey(k.key, false, k.modifiers),
            .modifiers_changed => |mods| self.input.onModifiersChanged(mods),
            else => {},
        }
        return false;
    }
};

/// windowkit 原生句柄 → 渲染层中立句柄。
///
/// 两边字段一一对应；转换放在窗口适配层，渲染层因此不需要 import windowkit，
/// Linux 分支也能脱离 wayland 链接项单独做类型检查。
fn convertNativeHandles(handles: windowkit.NativeHandles) render_api.NativeWindow {
    return switch (handles) {
        .win32 => |h| .{ .win32 = .{ .hwnd = h.hwnd, .hinstance = h.hinstance } },
        .wayland => |h| .{ .wayland = .{ .display = h.display, .surface = h.surface } },
        .appkit => |h| .{ .appkit = .{
            .ns_window = h.ns_window,
            .ns_view = h.ns_view,
            .metal_layer = h.metal_layer,
        } },
        .web => .{ .web = .{} },
    };
}
