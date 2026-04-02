const std = @import("std");

const win32 = @import("win32").everything;

pub const Input = struct {
    keyboard_state: [256]bool,
    mouse_state: [5]bool,
    mouse_x: i32,
    mouse_y: i32,
    mouse_delta_x: i32,
    mouse_delta_y: i32,
    mouse_wheel: i32,

    pub fn init() Input {
        return Input{
            .keyboard_state = [_]bool{false} ** 256,
            .mouse_state = [_]bool{false} ** 5,
            .mouse_x = 0,
            .mouse_y = 0,
            .mouse_delta_x = 0,
            .mouse_delta_y = 0,
            .mouse_wheel = 0,
        };
    }

    pub fn update(self: *Input) void {
        // 保存上一帧的鼠标位置
        const prev_mouse_x = self.mouse_x;
        const prev_mouse_y = self.mouse_y;

        // 更新键盘状态
        for (0..256) |i| {
            const key_state = win32.GetAsyncKeyState(@intCast(i));
            self.keyboard_state[i] = key_state < 0;
        }

        // 更新鼠标状态
        var mouse_pos: win32.POINT = undefined;
        _ = win32.GetCursorPos(&mouse_pos);
        self.mouse_x = mouse_pos.x;
        self.mouse_y = mouse_pos.y;

        // 计算鼠标 delta 值
        self.mouse_delta_x = self.mouse_x - prev_mouse_x;
        self.mouse_delta_y = self.mouse_y - prev_mouse_y;

        self.mouse_state[0] = win32.GetAsyncKeyState(@intFromEnum(win32.VK_LBUTTON)) < 0;
        self.mouse_state[1] = win32.GetAsyncKeyState(@intFromEnum(win32.VK_RBUTTON)) < 0;
        self.mouse_state[2] = win32.GetAsyncKeyState(@intFromEnum(win32.VK_MBUTTON)) < 0;
        self.mouse_state[3] = win32.GetAsyncKeyState(@intFromEnum(win32.VK_XBUTTON1)) < 0;
        self.mouse_state[4] = win32.GetAsyncKeyState(@intFromEnum(win32.VK_XBUTTON2)) < 0;
    }

    pub fn getMouseDelta(self: *Input) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_delta_x, .y = self.mouse_delta_y };
    }

    pub fn resetMouseDelta(self: *Input) void {
        self.mouse_delta_x = 0;
        self.mouse_delta_y = 0;
    }

    pub fn setMouseWheel(self: *Input, delta: i32) void {
        self.mouse_wheel = delta;
    }

    pub fn getMouseWheel(self: *Input) i32 {
        return self.mouse_wheel;
    }

    pub fn isKeyPressed(self: *Input, key_code: u8) bool {
        return self.keyboard_state[key_code];
    }

    pub fn isKeyPressedFromEnum(self: *Input, key: win32.VIRTUAL_KEY) bool {
        const key_code = @intFromEnum(key);
        if (key_code < 0 or key_code >= 256) return false;
        return self.keyboard_state[@intCast(key_code)];
    }

    pub fn isMouseButtonPressed(self: *Input, button_index: u32) bool {
        if (button_index >= self.mouse_state.len) return false;
        return self.mouse_state[button_index];
    }

    pub fn getMousePosition(self: *Input) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_x, .y = self.mouse_y };
    }

    pub fn isCtrlMouseWheel(self: *Input) bool {
        return self.isKeyPressedFromEnum(win32.VK_CONTROL) and self.mouse_wheel != 0;
    }

    pub fn getCtrlMouseWheelDelta(self: *Input) i32 {
        if (self.isKeyPressedFromEnum(win32.VK_CONTROL)) {
            return self.mouse_wheel;
        }
        return 0;
    }
};
