const std = @import("std");

const win32 = @import("win32").everything;
const L = win32.L;

pub const Window = struct {
    hwnd: win32.HWND,
    hdc: win32.HDC,
    allocator: std.mem.Allocator,
    running: bool,
    size_changed: bool,
    // 输入状态
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_delta_x: i32 = 0,
    mouse_delta_y: i32 = 0,
    mouse_wheel: i32 = 0,
    mouse_buttons: [5]bool = [_]bool{false} ** 5,
    keyboard_state: [256]bool = [_]bool{false} ** 256,

    const CLASS_NAME = L("ZigDx11WindowClass");

    // 窗口实例指针映射，用于在窗口过程中访问Window实例
    var window_instances: std.AutoHashMap(win32.HWND, *Window) = undefined;

    fn wndProc(
        hwnd: win32.HWND,
        uMsg: u32,
        wParam: win32.WPARAM,
        lParam: win32.LPARAM,
    ) callconv(.winapi) win32.LRESULT {
        // 从窗口获取用户数据
        const window_ptr_value = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
        if (window_ptr_value != 0) {
            // 将isize值转换回Window指针
            const window_ptr: *Window = @ptrFromInt(@as(usize, @bitCast(window_ptr_value)));

            switch (uMsg) {
                win32.WM_DESTROY => {
                    win32.PostQuitMessage(0);
                    return 0;
                },
                win32.WM_PAINT => {
                    var ps: win32.PAINTSTRUCT = undefined;
                    const hdc = win32.BeginPaint(hwnd, &ps);
                    const background_brush = win32.GetStockObject(win32.BLACK_BRUSH);
                    _ = win32.FillRect(hdc, &ps.rcPaint, @ptrCast(background_brush));
                    _ = win32.EndPaint(hwnd, &ps);
                    return 0;
                },
                win32.WM_SIZE => {
                    // 设置大小变化标志
                    window_ptr.size_changed = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MOUSEMOVE => {
                    // 处理鼠标移动
                    const lParam_usize = @as(usize, @bitCast(lParam));
                    const x = @as(u16, @truncate(lParam_usize));
                    const y = @as(u16, @truncate(lParam_usize >> 16));
                    const new_mouse_x = @as(i16, @bitCast(x));
                    const new_mouse_y = @as(i16, @bitCast(y));

                    // 计算鼠标 delta
                    window_ptr.mouse_delta_x = new_mouse_x - window_ptr.mouse_x;
                    window_ptr.mouse_delta_y = new_mouse_y - window_ptr.mouse_y;

                    // 更新鼠标位置
                    window_ptr.mouse_x = new_mouse_x;
                    window_ptr.mouse_y = new_mouse_y;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_LBUTTONDOWN => {
                    window_ptr.mouse_buttons[0] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_LBUTTONUP => {
                    window_ptr.mouse_buttons[0] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_RBUTTONDOWN => {
                    window_ptr.mouse_buttons[1] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_RBUTTONUP => {
                    window_ptr.mouse_buttons[1] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MBUTTONDOWN => {
                    window_ptr.mouse_buttons[2] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MBUTTONUP => {
                    window_ptr.mouse_buttons[2] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_XBUTTONDOWN => {
                    const button = (@as(u16, @truncate(wParam >> 16)) & 0x000F);
                    if (button == 1) {
                        window_ptr.mouse_buttons[3] = true;
                    } else if (button == 2) {
                        window_ptr.mouse_buttons[4] = true;
                    }
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_XBUTTONUP => {
                    const button = (@as(u16, @truncate(wParam >> 16)) & 0x000F);
                    if (button == 1) {
                        window_ptr.mouse_buttons[3] = false;
                    } else if (button == 2) {
                        window_ptr.mouse_buttons[4] = false;
                    }
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MOUSEWHEEL => {
                    // 处理鼠标滚轮
                    const delta = @as(i16, @bitCast(@as(u16, @truncate(wParam >> 16))));
                    window_ptr.mouse_wheel = delta;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_KEYDOWN => {
                    // 处理键盘按下
                    const key_code = @as(u8, @truncate(wParam));
                    window_ptr.keyboard_state[key_code] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_KEYUP => {
                    // 处理键盘释放
                    const key_code = @as(u8, @truncate(wParam));
                    window_ptr.keyboard_state[key_code] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                else => return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam),
            }
        } else {
            switch (uMsg) {
                win32.WM_DESTROY => {
                    win32.PostQuitMessage(0);
                    return 0;
                },
                else => return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam),
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator) !*Window {
        const wc = win32.WNDCLASSW{
            .style = .{},
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = win32.GetModuleHandleW(null),
            .hIcon = null,
            .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
            .hbrBackground = win32.GetStockObject(win32.WHITE_BRUSH),
            .lpszMenuName = null,
            .lpszClassName = CLASS_NAME,
        };

        if (win32.RegisterClassW(&wc) == 0)
            return error.FailedToRegisterClass;

        const hwnd = win32.CreateWindowExW(
            .{},
            CLASS_NAME,
            L("ZigDx11 Engine"),
            win32.WS_OVERLAPPEDWINDOW,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            1280,
            720,
            null,
            null,
            wc.hInstance,
            null,
        ) orelse return error.FailedToCreateWindow;

        const hdc = win32.GetDC(hwnd) orelse return error.FailedToGetDeviceContext;

        // 为窗口分配内存
        const window_ptr = try allocator.create(Window);

        window_ptr.* = Window{
            .allocator = allocator,
            .hwnd = hwnd,
            .hdc = hdc,
            .running = true,
            .size_changed = false,
        };

        _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @as(isize, @intCast(@intFromPtr(window_ptr))));

        return window_ptr;
    }

    pub fn deinit(self: *Window) void {
        _ = win32.ReleaseDC(self.hwnd, self.hdc);
        _ = win32.DestroyWindow(self.hwnd);

        // 清理窗口实例内存
        self.allocator.destroy(self);
    }

    // 获取窗口客户区域大小
    pub fn getClientSize(self: *Window) struct { width: u32, height: u32 } {
        var client_rect: win32.RECT = undefined;
        _ = win32.GetClientRect(self.hwnd, &client_rect);

        return .{
            .width = @intCast(client_rect.right - client_rect.left),
            .height = @intCast(client_rect.bottom - client_rect.top),
        };
    }

    pub fn show(self: *Window) void {
        _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
        _ = win32.UpdateWindow(self.hwnd);
    }

    pub fn processMessages(self: *Window) bool {
        var msg: win32.MSG = undefined;
        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
            if (msg.message == win32.WM_QUIT) {
                self.running = false;
                return false;
            }

            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
        return self.running;
    }

    // 输入状态获取方法
    pub fn getMousePosition(self: *Window) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_x, .y = self.mouse_y };
    }

    pub fn getMouseDelta(self: *Window) struct { x: i32, y: i32 } {
        return .{ .x = self.mouse_delta_x, .y = self.mouse_delta_y };
    }

    pub fn getMouseWheel(self: *Window) i32 {
        return self.mouse_wheel;
    }

    pub fn isMouseButtonPressed(self: *Window, button_index: u32) bool {
        if (button_index < self.mouse_buttons.len) {
            return self.mouse_buttons[button_index];
        }
        return false;
    }

    pub fn isKeyPressed(self: *Window, key_code: u8) bool {
        return self.keyboard_state[key_code];
    }

    pub fn isKeyPressedFromEnum(self: *Window, key: win32.VIRTUAL_KEY) bool {
        const key_code = @intFromEnum(key);
        if (key_code < 256) {
            return self.keyboard_state[@intCast(key_code)];
        }
        return false;
    }

    // 重置输入状态
    pub fn resetMouseDelta(self: *Window) void {
        self.mouse_delta_x = 0;
        self.mouse_delta_y = 0;
    }

    pub fn resetMouseWheel(self: *Window) void {
        self.mouse_wheel = 0;
    }
};
