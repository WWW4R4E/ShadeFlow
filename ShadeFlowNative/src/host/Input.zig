const std = @import("std");
const wkInput = @import("windowkit").input;

/// 宿主侧输入状态：把 windowkit 的平台无关 `InputEvent` 收敛成"本帧可查询
/// 的按住 / 位置状态"。
///
/// 这一层住在宿主（`host/`）而不是引擎里：引擎不认识输入设备，只接收宿主
/// 翻译好的命令。WinUI 3 宿主（`capi.zig`）在 C# 侧做同样的翻译。
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
    /// 滚轮事件**当下**的修饰键。
    ///
    /// 缩放判定必须用它，不能用当前的 `modifiers`：滚轮量是一次性的，等到
    /// 帧边界再回头看"现在按着 Ctrl 没有"，会出现"先无 Ctrl 滚一下、再按住
    /// Ctrl，下一帧凭空缩放"。
    wheel_modifiers: wkInput.Modifiers,
    /// 鼠标位置是否已经建立锚点。第一次 `onMouseMove` 只定锚点、不产生位移，
    /// 否则启动后第一次移动会从 (0,0) 算起，攒出一个巨大的假位移。
    has_position: bool,

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
            .wheel_modifiers = .{},
            .has_position = false,
        };
    }

    // =========================================================================
    // 事件入口 —— 由 host/Host.zig 的 onInput 调用
    // =========================================================================

    pub fn onKey(self: *Input, key: wkInput.KeyTag, down: bool, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        self.keys_down.setPresent(key, down);
    }

    pub fn onMouseButton(self: *Input, button: wkInput.MouseButton, down: bool, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        self.mouse_state[@intFromEnum(button)] = down;

        // 中键按下：清掉上一段拖动残留的位移。相机命令在帧边界统一发出
        // （那时中键已经按下），不清理的话第一帧会把上一次的尾巴一次性
        // 灌进相机，表现为"按下中键的瞬间相机跳一下"。
        if (down and button == .middle) {
            self.mouse_delta_x = 0;
            self.mouse_delta_y = 0;
        }
    }

    /// `x` / `y` 为引擎坐标系（客户区物理像素，见 `Host.toEnginePx`）。
    pub fn onMouseMove(self: *Input, x: i32, y: i32, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;

        // 第一次只定锚点：位移是相对上一次位置算的，没有锚点就会从 (0,0)
        // 算起，攒出一个巨大的假位移。
        if (!self.has_position) {
            self.has_position = true;
            self.mouse_x = x;
            self.mouse_y = y;
            return;
        }

        const delta_x = x - self.mouse_x;
        const delta_y = y - self.mouse_y;
        self.mouse_x = x;
        self.mouse_y = y;

        // 位移只在中键拖动期间累计。中键没按下时累计下来的位移到了按下
        // 那一刻就是陈旧的，会让相机在按下第一帧跳一下；而且没有消费者
        // 的时候一直累加还会溢出。
        if (!self.isMouseButtonDown(.middle)) return;

        self.mouse_delta_x += delta_x;
        self.mouse_delta_y += delta_y;
    }

    /// 滚轮是行为增量，按 Win32 WHEEL_DELTA 折算成整数格数。
    ///
    /// 修饰键在这里一并记下：缩放判定要用"滚动当下"的修饰键。
    pub fn onScroll(self: *Input, delta_y: f64, modifiers: wkInput.Modifiers) void {
        self.modifiers = modifiers;
        self.wheel_modifiers = modifiers;
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
    ///
    /// 判定用**滚轮事件当下**的修饰键（`wheel_modifiers`），不是当前的
    /// `modifiers`：滚轮量留到帧边界才消费时，当前的修饰键可能已经变了。
    pub fn isZoomInput(self: *Input) bool {
        return self.wheel_modifiers.ctrl and self.mouse_wheel != 0;
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

// =============================================================================
// 测试
// =============================================================================

test "中键拖动期间位移累加，而不是只留最后一次事件" {
    var input = Input.init();
    input.onMouseButton(.middle, true, .{});

    input.onMouseMove(100, 100, .{});
    input.onMouseMove(110, 105, .{});
    input.onMouseMove(115, 105, .{});

    const delta = input.getMouseDelta();
    try std.testing.expectEqual(@as(i32, 15), delta.x);
    try std.testing.expectEqual(@as(i32, 5), delta.y);
}

test "中键没按下时不累计位移" {
    var input = Input.init();

    input.onMouseMove(100, 100, .{});
    input.onMouseMove(200, 200, .{});

    const delta = input.getMouseDelta();
    try std.testing.expectEqual(@as(i32, 0), delta.x);
    try std.testing.expectEqual(@as(i32, 0), delta.y);
}

test "中键按下时清掉残留位移，避免相机在按下第一帧跳一下" {
    var input = Input.init();

    // 先拖一段（中键按下 → 移动 → 抬起）
    input.onMouseButton(.middle, true, .{});
    input.onMouseMove(100, 100, .{});
    input.onMouseMove(130, 100, .{});
    input.onMouseButton(.middle, false, .{});

    // 残留没被消费掉
    try std.testing.expectEqual(@as(i32, 30), input.getMouseDelta().x);

    // 再按下中键：残留应当被清掉
    input.onMouseButton(.middle, true, .{});
    try std.testing.expectEqual(@as(i32, 0), input.getMouseDelta().x);

    // 之后的新位移从 0 开始重新累计
    input.onMouseMove(140, 100, .{});
    try std.testing.expectEqual(@as(i32, 10), input.getMouseDelta().x);
}

test "滚轮量是按 Win32 WHEEL_DELTA 折算的格数，取走即清" {
    var input = Input.init();

    input.onScroll(1.0, .{});
    try std.testing.expectEqual(@as(i32, 120), input.getMouseWheel());

    input.resetMouseWheel();
    try std.testing.expectEqual(@as(i32, 0), input.getMouseWheel());
}

test "缩放只在 Ctrl 按住时成立，且判定用滚动事件当下的修饰键" {
    var input = Input.init();

    // 无 Ctrl 滚一下：留下滚轮量，但不构成缩放输入
    input.onScroll(1.0, .{});
    try std.testing.expect(!input.isZoomInput());

    // 之后只按下 Ctrl（没有新的滚动事件）：不该变成缩放输入
    input.onModifiersChanged(.{ .ctrl = true });
    try std.testing.expect(!input.isZoomInput());

    // 带 Ctrl 再滚一次：才是缩放输入
    input.onScroll(1.0, .{ .ctrl = true });
    try std.testing.expect(input.isZoomInput());
}
