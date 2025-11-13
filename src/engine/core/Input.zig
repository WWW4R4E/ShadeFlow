const std = @import("std");

const win32 = @import("win32").everything;

pub const Input = struct {
    keyboard_state: [256]bool,
    mouse_state: [5]bool,
    mouse_x: i32,
    mouse_y: i32,

    pub fn init() Input {
        return Input{
            .keyboard_state = [_]bool{false} ** 256,
            .mouse_state = [_]bool{false} ** 5,
            .mouse_x = 0,
            .mouse_y = 0,
        };
    }

    pub fn update(self: *Input) void {
        // 更新键盘状态
        for (0..256) |i| {
            self.keyboard_state[i] = (win32.GetAsyncKeyState(@intCast(i)) & 0x8000) != 0;
        }

        // 更新鼠标状态
        var mouse_pos: win32.POINT = undefined;
        _ = win32.GetCursorPos(&mouse_pos);
        self.mouse_x = mouse_pos.x;
        self.mouse_y = mouse_pos.y;

        self.mouse_state[0] = (win32.GetAsyncKeyState(win32.VK_LBUTTON) & 0x8000) != 0;
        self.mouse_state[1] = (win32.GetAsyncKeyState(win32.VK_RBUTTON) & 0x8000) != 0;
        self.mouse_state[2] = (win32.GetAsyncKeyState(win32.VK_MBUTTON) & 0x8000) != 0;
        self.mouse_state[3] = (win32.GetAsyncKeyState(win32.VK_XBUTTON1) & 0x8000) != 0;
        self.mouse_state[4] = (win32.GetAsyncKeyState(win32.VK_XBUTTON2) & 0x8000) != 0;
    }

    pub fn isKeyPressed(self: *Input, key_code: u8) bool {
        return self.keyboard_state[key_code];
    }

    pub fn isMouseButtonPressed(self: *Input, button_index: u32) bool {
        if (button_index >= self.mouse_state.len) return false;
        return self.mouse_state[button_index];
    }

    pub fn getMousePosition(self: *Input) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_x, .y = self.mouse_y };
    }
};
