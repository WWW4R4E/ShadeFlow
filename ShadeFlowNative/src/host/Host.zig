//! 独立窗口宿主 —— windowkit 事件 → 引擎命令。
//!
//! 引擎（`engine/`）不认识任何输入设备：它只提供 `cameraZoom` / `cameraPan` /
//! `cameraOrbit` / `cameraSelfRotate` / `pickAt` 这几个命令入口，由宿主把平台
//! 的原始事件翻译成命令后调用。WinUI 3 宿主（`capi.zig`）走的是同一批命令
//! 入口，只是翻译发生在 C# 侧。
//!
//! 职责分工：
//!
//! - **窗口生命周期**：windowkit 的 `Platform` / `PlatformWindow` 由 `main.zig`
//!   创建与销毁（它需要活在事件循环之外）；
//! - **事件翻译**：本模块把 `InputEvent` 落成 `Input` 状态，并在帧边界把状态
//!   折算成引擎命令；
//! - **坐标归一**：把平台坐标统一成客户区**物理像素**，和 `Viewport` / `Picker`
//!   同一坐标系。
//!
//! 注意 windowkit 的 `setUserData` 只有**一个**槽位：`main.zig` 初始化时写入
//! `*Host` 一次，之后绝不再调 `setUserData`——回调里 `getUserData` 会拿到被
//! `@ptrCast` 坏掉的对象，崩溃点会跑到毫不相关的地方。

const std = @import("std");
const builtin = @import("builtin");

const windowkit = @import("windowkit");
const wkInput = windowkit.input;

const Engine = @import("shadeflow_engine").Engine;
const Input = @import("Input.zig").Input;

/// 宿主上下文：引擎引用 + 输入状态 + 帧边界的待办。
///
/// 地址必须稳定（`main.zig` 把它放在栈上，活得比事件循环久），因为 windowkit
/// 的 user_data 存的就是这个指针。
pub const Host = struct {
    engine: *Engine,
    input: Input = Input.init(),
    /// 窗口尺寸变化标志：resize 回调只置位，交换链在帧边界重建。
    size_changed: bool = false,
    /// 上一帧鼠标左键状态，用来把拾取限制在"按下"的那一帧。
    mouse_left_prev: bool = false,

    pub fn init(engine: *Engine) Host {
        return .{ .engine = engine };
    }

    // =========================================================================
    // 事件
    // =========================================================================

    /// 输入事件 → 输入状态。命令在帧边界统一发出（见 `onFrame`）。
    pub fn onInput(self: *Host, win: *windowkit.PlatformWindow, event: wkInput.InputEvent) void {
        switch (event) {
            .mouse_moved, .mouse_dragged => |m| {
                const pos = toEnginePx(win, m.position.x, m.position.y);
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
    }

    /// 尺寸变化：只置位，实际重建交换链放在帧边界。
    pub fn onResize(self: *Host, win: *windowkit.PlatformWindow, width: f64, height: f64) void {
        // windowkit 传的是逻辑像素，这里只做诊断；引擎侧统一用
        // `framebufferSize()`（物理像素）重建交换链，两者都打出来方便对照。
        const fb = win.framebufferSize();
        std.log.info(
            "窗口尺寸变化：逻辑 {d:.0}x{d:.0}，物理 {d}x{d}（scale {d:.2}）",
            .{ width, height, fb.width_px, fb.height_px, win.getScaleFactor() },
        );
        self.size_changed = true;
    }

    /// 帧边界：输入状态 → 引擎命令 → 推进一帧 → 渲染。
    pub fn onFrame(self: *Host, win: *windowkit.PlatformWindow) void {
        self.applyCameraCommands();
        self.applyPick();
        self.applyResize(win);

        self.engine.update();
        self.engine.render();

        // 连续渲染：预约下一帧节拍（需要 needs_render 重新置位）。
        win.requestRender();
    }

    // =========================================================================
    // 输入 → 命令
    // =========================================================================

    /// 相机命令：缩放 = Ctrl + 滚轮；平移 = Ctrl + 中键；
    /// 公转 = 中键（不按 Alt / Ctrl）；自转 = Alt + 中键。
    ///
    /// 位移在每帧只应用一次：相机的旋转是四元数乘法，一帧里拆成很多次
    /// 小旋转和一次大旋转结果并不相同，按帧合并才和"一帧拖了多远"对应。
    fn applyCameraCommands(self: *Host) void {
        const input = &self.input;

        if (input.isZoomInput()) {
            const wheel_delta = input.getMouseWheel();
            self.engine.cameraZoom(@as(f32, @floatFromInt(wheel_delta)));
            input.resetMouseWheel();
        }

        if (input.isPanInput()) {
            const delta = input.getMouseDelta();
            self.engine.cameraPan(
                @as(f32, @floatFromInt(delta.x)),
                @as(f32, @floatFromInt(delta.y)),
            );
            input.resetMouseDelta();
        }

        if (input.isOrbitInput()) {
            const delta = input.getMouseDelta();
            self.engine.cameraOrbit(
                @as(f32, @floatFromInt(delta.x)),
                @as(f32, @floatFromInt(delta.y)),
            );
            input.resetMouseDelta();
        }

        if (input.isSelfRotateInput()) {
            const delta = input.getMouseDelta();
            self.engine.cameraSelfRotate(
                @as(f32, @floatFromInt(delta.x)),
                @as(f32, @floatFromInt(delta.y)),
            );
            input.resetMouseDelta();
        }
    }

    /// 鼠标左键点击选取物体：只在按下的那一帧拾取。
    /// 物体每帧都在自转，按住期间重复拾取会让选中结果来回跳。
    fn applyPick(self: *Host) void {
        const left_down = self.input.isMouseButtonDown(.left);
        if (left_down and !self.mouse_left_prev) {
            const pos = self.input.getMousePosition();
            self.engine.pickAt(
                @as(f32, @floatFromInt(pos.x)),
                @as(f32, @floatFromInt(pos.y)),
            );
        }
        self.mouse_left_prev = left_down;
    }

    /// 尺寸变化 → 重建交换链。取的是**当前**的帧缓冲尺寸，不是 resize 事件
    /// 那一刻的尺寸：连续拖拽窗口时中间尺寸往往已经被合并掉了。
    fn applyResize(self: *Host, win: *windowkit.PlatformWindow) void {
        if (!self.size_changed) return;
        self.size_changed = false;

        const px = win.framebufferSize();
        self.engine.resizeRenderer(px.width_px, px.height_px) catch |err| {
            std.log.err("处理窗口大小变化失败: {s}", .{@errorName(err)});
        };
    }
};

/// 鼠标坐标 → 引擎坐标（客户区物理像素）。
///
/// 后端差异（经验证）：
/// - Windows：windowkit 直发 `WM_MOUSEMOVE` 的 lParam 客户区坐标，
///   PerMonitorV2 下该值就是**物理像素**，不要再乘 scale；
/// - macOS：AppKit 的 view 坐标是**逻辑点**（且 `isFlipped` 已把原点翻到
///   左上角），要乘 `backingScaleFactor` 才能和 `framebufferSize()` 对齐；
/// - Linux/Wayland：pointer 坐标同样是 surface-local 逻辑坐标，同样乘
///   `scale_factor`。
fn toEnginePx(win: *windowkit.PlatformWindow, x: f64, y: f64) struct { x: i32, y: i32 } {
    const scale: f64 = switch (builtin.os.tag) {
        .windows => 1.0,
        else => win.getScaleFactor(),
    };
    return .{
        .x = @intFromFloat(@round(x * scale)),
        .y = @intFromFloat(@round(y * scale)),
    };
}
