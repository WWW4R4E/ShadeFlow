const std = @import("std");
const wkInput = @import("windowkit").input;

/// 引擎侧输入状态：把 windowkit 的平台无关 `InputEvent` 收敛成"本帧可查询
/// 的按住 / 位置状态"。
pub const Input = struct {
    /// windowkit 的 `KeyTag` 是按 US ANSI 物理位置命名的纯枚举，没有对应的
    /// 平台原始键码，直接用 `EnumSet` 按枚举值建位图，别再假设它是小整数。
    const KeySet = std.enums.EnumSet(wkInput.KeyTag);
    keys_down: KeySet,
    modifiers: wkInput.Modifiers,
    mouse_state: [3]bool,
    mouse_x: i32,
    mouse_y: i32,
    mouse_delta_x: i32,
    mouse_delta_y: i32,
    mouse_wheel: i32,

    pub fn init() Input {
        return .{
            .keys_down = KeySet.empty,
            .modifiers = .{},
            .mouse_state = @splat(false),
            .mouse_x = 0,
            .mouse_y = 0,
            .mouse_delta_x = 0,
            .mouse_delta_y = 0,
            .mouse_wheel = 0,
        };
    }

    // =========================================================================
    // 事件入口 —— 由 optional/Window.zig 的 translateEvent 调用
    // =========================================================================

    pub fn onKey(self: *Input, key: wkInput.KeyTag, down: bool, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        self.keys_down.setPresent(key, down);
    }

    pub fn onMouseButton(self: *Input, button: wkInput.MouseButton, down: bool, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        self.mouse_state[@intFromEnum(button)] = down;
    }

    /// `x` / `y` 为引擎坐标系（客户区物理像素，见 `Window.toEnginePx`）。
    pub fn onMouseMove(self: *Input, x: i32, y: i32, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        self.mouse_delta_x = x - self.mouse_x;
        self.mouse_delta_y = y - self.mouse_y;
        self.mouse_x = x;
        self.mouse_y = y;
    }

    pub fn onScroll(self: *Input, delta_y: f64, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        // windowkit 滚轮是行为增量，引擎按 Win32 WHEEL_DELTA 处理。
        self.mouse_wheel = @intFromFloat(@round(delta_y * 120.0));
    }

    pub fn onModifiersChanged(self: *Input, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
    }

    // =========================================================================
    // 查询
    // =========================================================================

    pub fn getMouseDelta(self: *Input) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_delta_x, .y = self.mouse_delta_y };
    }

    pub fn resetMouseDelta(self: *Input) void {
        self.mouse_delta_x = 0;
        self.mouse_delta_y = 0;
    }

    pub fn getMouseWheel(self: *Input) i32 {
        return self.mouse_wheel;
    }

    pub fn resetMouseWheel(self: *Input) void {
        self.mouse_wheel = 0;
    }

    pub fn getMousePosition(self: *Input) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_x, .y = self.mouse_y };
    }

    pub fn isKeyDown(self: *const Input, key: wkInput.KeyTag) bool {
        return self.keys_down.contains(key);
    }

    pub fn isMouseButtonDown(self: *const Input, button: wkInput.MouseButton) bool {
        return self.mouse_state[@intFromEnum(button)];
    }

    // =========================================================================
    // 相机操作判定
    // =========================================================================

    /// 缩放：Ctrl + 滚轮。
    pub fn isZoomInput(self: *Input) bool {
        return self.modifiers.ctrl and self.mouse_wheel != 0;
    }

    /// 平移：Ctrl + 中键。
    pub fn isPanInput(self: *Input) bool {
        return self.modifiers.ctrl and self.isMouseButtonDown(.middle);
    }

    /// 绕中心公转：中键，且不按 Alt / Ctrl。
    pub fn isOrbitInput(self: *Input) bool {
        return !self.modifiers.alt and !self.modifiers.ctrl and self.isMouseButtonDown(.middle);
    }

    /// 自转：Alt + 中键（不按 Ctrl）。
    pub fn isSelfRotateInput(self: *Input) bool {
        return self.modifiers.alt and !self.modifiers.ctrl and self.isMouseButtonDown(.middle);
    }
};
