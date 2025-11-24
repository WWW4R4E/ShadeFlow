const std = @import("std");

const win32 = @import("win32").everything;
const L = win32.L;


pub const Window = struct {
    hwnd: win32.HWND,
    hdc: win32.HDC,
    allocator: std.mem.Allocator,
    running: bool,
    size_changed: bool,

    const CLASS_NAME = L("ZigDx11WindowClass");
    var static_data_initialized: bool = false;

    // 窗口实例指针映射，用于在窗口过程中访问Window实例
    var window_instances: std.AutoHashMap(win32.HWND, *Window) = undefined;

    // 初始化静态数据
    fn initStaticData() !void {
        window_instances = std.AutoHashMap(win32.HWND, *Window).init(std.heap.page_allocator);
        static_data_initialized = true;
    }

    // 清理静态数据
    fn deinitStaticData() void {
        if (static_data_initialized) {
            window_instances.deinit();
        }
    }

    fn wndProc(
        hwnd: win32.HWND,
        uMsg: u32,
        wParam: win32.WPARAM,
        lParam: win32.LPARAM,
    ) callconv(.winapi) win32.LRESULT {
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
                // 从窗口获取用户数据
                const window_ptr_value = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
                if (window_ptr_value != 0) {
                    // 将isize值转换回Window指针
                    const window_ptr: *Window = @ptrFromInt(@as(usize, @bitCast(window_ptr_value)));
                    // 设置大小变化标志
                    window_ptr.size_changed = true;
                }
                return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
            },
            else => return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam),
        }
    }

    pub fn init(allocator: std.mem.Allocator) !*Window {
        if (!static_data_initialized) {
            try initStaticData();
        }

        const wc = win32.WNDCLASSW{
            .style = .{},
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = win32.GetModuleHandleW(null),
            .hIcon = null,
            .hCursor = null,
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
};
