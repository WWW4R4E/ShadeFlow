const std = @import("std");
const win32 = @import("win32").everything;
const L = win32.L;

const Input = @import("Input.zig").Input;

pub const Window = struct {
    hwnd: win32.HWND,
    hdc: win32.HDC,
    allocator: std.mem.Allocator,
    running: bool,
    size_changed: bool,
    input: Input,
    // 自定义拖拽/缩放状态（替代 DefWindowProc 模态循环）
    is_dragging: bool = false,
    is_resizing: bool = false,
    drag_offset_x: i32 = 0,
    drag_offset_y: i32 = 0,
    resize_edge: u32 = 0,
    resize_rect: win32.RECT = undefined,

    const MIN_WIDTH: i32 = 320;
    const MIN_HEIGHT: i32 = 240;
    const CLASS_NAME = L("ZigDx11WindowClass");

    fn resizeWindow(self: *Window, hwnd: win32.HWND, sx: i32, sy: i32) void {
        var r = self.resize_rect;

        switch (self.resize_edge) {
            win32.HTLEFT => r.left = sx,
            win32.HTRIGHT => r.right = sx,
            win32.HTTOP => r.top = sy,
            win32.HTBOTTOM => r.bottom = sy,
            win32.HTTOPLEFT => {
                r.left = sx;
                r.top = sy;
            },
            win32.HTTOPRIGHT => {
                r.right = sx;
                r.top = sy;
            },
            win32.HTBOTTOMLEFT => {
                r.left = sx;
                r.bottom = sy;
            },
            win32.HTBOTTOMRIGHT => {
                r.right = sx;
                r.bottom = sy;
            },
            else => return,
        }

        if (r.right - r.left < MIN_WIDTH) {
            if (r.left != self.resize_rect.left) r.left = r.right - MIN_WIDTH else r.right = r.left + MIN_WIDTH;
        }
        if (r.bottom - r.top < MIN_HEIGHT) {
            if (r.top != self.resize_rect.top) r.top = r.bottom - MIN_HEIGHT else r.bottom = r.top + MIN_HEIGHT;
        }

        _ = win32.SetWindowPos(hwnd, null, r.left, r.top, r.right - r.left, r.bottom - r.top, .{
            .NOZORDER = 1,
            .NOACTIVATE = 1,
        });
        self.size_changed = true;
    }

    fn wndProc(
        hwnd: win32.HWND,
        uMsg: u32,
        wParam: win32.WPARAM,
        lParam: win32.LPARAM,
    ) callconv(.winapi) win32.LRESULT {
        const window_ptr_value = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
        if (window_ptr_value != 0) {
            const window_ptr: *Window = @ptrFromInt(@as(usize, @bitCast(window_ptr_value)));

            switch (uMsg) {
                win32.WM_DESTROY => {
                    win32.PostQuitMessage(0);
                    return 0;
                },
                win32.WM_NCHITTEST => {
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_NCLBUTTONDOWN => {
                    const hit_test = @as(u16, @truncate(@as(u32, @intCast(wParam))));
                    const lParam_usize = @as(usize, @bitCast(lParam));
                    const screen_x = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(lParam_usize)))));
                    const screen_y = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(lParam_usize >> 16)))));

                    switch (hit_test) {
                        win32.HTCAPTION => {
                            var rect: win32.RECT = undefined;
                            _ = win32.GetWindowRect(hwnd, &rect);
                            window_ptr.drag_offset_x = screen_x - rect.left;
                            window_ptr.drag_offset_y = screen_y - rect.top;
                            window_ptr.is_dragging = true;
                            _ = win32.SetCapture(hwnd);
                            return 0;
                        },
                        win32.HTLEFT, win32.HTRIGHT, win32.HTTOP, win32.HTBOTTOM, win32.HTTOPLEFT, win32.HTTOPRIGHT, win32.HTBOTTOMLEFT, win32.HTBOTTOMRIGHT => {
                            window_ptr.resize_edge = hit_test;
                            _ = win32.GetWindowRect(hwnd, &window_ptr.resize_rect);
                            window_ptr.is_resizing = true;
                            _ = win32.SetCapture(hwnd);
                            return 0;
                        },
                        else => return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam),
                    }
                },
                win32.WM_MOUSEMOVE => {
                    const lParam_usize = @as(usize, @bitCast(lParam));
                    const cx = @as(i16, @bitCast(@as(u16, @truncate(lParam_usize))));
                    const cy = @as(i16, @bitCast(@as(u16, @truncate(lParam_usize >> 16))));

                    window_ptr.input.mouse_delta_x = @as(i32, cx) - window_ptr.input.mouse_x;
                    window_ptr.input.mouse_delta_y = @as(i32, cy) - window_ptr.input.mouse_y;
                    window_ptr.input.mouse_x = @as(i32, cx);
                    window_ptr.input.mouse_y = @as(i32, cy);

                    if (window_ptr.is_dragging) {
                        var pt: win32.POINT = .{ .x = @intCast(cx), .y = @intCast(cy) };
                        _ = win32.ClientToScreen(hwnd, &pt);
                        _ = win32.SetWindowPos(hwnd, null, pt.x - window_ptr.drag_offset_x, pt.y - window_ptr.drag_offset_y, 0, 0, .{
                            .NOSIZE = 1,
                            .NOZORDER = 1,
                            .NOACTIVATE = 1,
                        });
                        return 0;
                    }

                    if (window_ptr.is_resizing) {
                        var pt: win32.POINT = .{ .x = @intCast(cx), .y = @intCast(cy) };
                        _ = win32.ClientToScreen(hwnd, &pt);
                        window_ptr.resizeWindow(hwnd, pt.x, pt.y);
                        return 0;
                    }

                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                // win32.WM_NCMOUSEMOVE => {
                //     const lParam_usize = @as(usize, @bitCast(lParam));
                //     const sx = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(lParam_usize)))));
                //     const sy = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(lParam_usize >> 16)))));

                //     if (window_ptr.is_dragging) {
                //         _ = win32.SetWindowPos(hwnd, null, sx - window_ptr.drag_offset_x, sy - window_ptr.drag_offset_y, 0, 0, .{
                //             .NOZORDER = 1,
                //             .NOACTIVATE = 1,
                //         });
                //         return 0;
                //     }

                //     if (window_ptr.is_resizing) {
                //         window_ptr.resizeWindow(hwnd, sx, sy);
                //         return 0;
                //     }
                //     return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                // },
                win32.WM_LBUTTONUP => {
                    if (window_ptr.is_dragging or window_ptr.is_resizing) {
                        window_ptr.is_dragging = false;
                        window_ptr.is_resizing = false;
                        _ = win32.ReleaseCapture();
                        return 0;
                    }
                    window_ptr.input.mouse_state[0] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_LBUTTONDOWN => {
                    window_ptr.input.mouse_state[0] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_RBUTTONDOWN => {
                    window_ptr.input.mouse_state[1] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_RBUTTONUP => {
                    window_ptr.input.mouse_state[1] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MBUTTONDOWN => {
                    window_ptr.input.mouse_state[2] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MBUTTONUP => {
                    window_ptr.input.mouse_state[2] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_XBUTTONDOWN => {
                    const button = (@as(u16, @truncate(wParam >> 16)) & 0x000F);
                    if (button == 1) window_ptr.input.mouse_state[3] = true else if (button == 2) window_ptr.input.mouse_state[4] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_XBUTTONUP => {
                    const button = (@as(u16, @truncate(wParam >> 16)) & 0x000F);
                    if (button == 1) window_ptr.input.mouse_state[3] = false else if (button == 2) window_ptr.input.mouse_state[4] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_MOUSEWHEEL => {
                    const delta = @as(i16, @bitCast(@as(u16, @truncate(wParam >> 16))));
                    window_ptr.input.mouse_wheel = delta;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_KEYDOWN => {
                    window_ptr.input.keyboard_state[@as(u8, @truncate(wParam))] = true;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_KEYUP => {
                    window_ptr.input.keyboard_state[@as(u8, @truncate(wParam))] = false;
                    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
                },
                win32.WM_SIZE => {
                    window_ptr.size_changed = true;
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

        const window_ptr = try allocator.create(Window);

        window_ptr.* = Window{
            .allocator = allocator,
            .hwnd = hwnd,
            .hdc = hdc,
            .running = true,
            .size_changed = false,
            .input = Input.init(),
        };

        _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @as(isize, @intCast(@intFromPtr(window_ptr))));

        return window_ptr;
    }

    pub fn deinit(self: *Window) void {
        _ = win32.ReleaseDC(self.hwnd, self.hdc);
        _ = win32.DestroyWindow(self.hwnd);
        self.allocator.destroy(self);
    }

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

    pub fn getInput(self: *Window) *Input {
        return &self.input;
    }
};
